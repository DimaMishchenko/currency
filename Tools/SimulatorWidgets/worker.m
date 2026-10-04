#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <unistd.h>

static id objectMessage(id receiver, const char *selectorName) {
    SEL selector = sel_registerName(selectorName);
    if (![receiver respondsToSelector:selector]) {
        [NSException raise:@"UnavailableSelector" format:@"%@ does not implement %s", receiver, selectorName];
    }
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static void saveJSON(NSDictionary *value, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"SimulatorWidgets cannot write %@: %@", path, error);
    }
}

static NSString *requiredString(NSDictionary *command, NSString *key) {
    id value = command[key];
    if (![value isKindOfClass:NSString.class] || ![value length]) {
        [NSException raise:@"InvalidCommand" format:@"%@ must be a nonempty string", key];
    }
    return value;
}

static SEL requireMethod(id receiver, const char *name, const char *encoding) {
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod([receiver class], selector);
    if (!method || strcmp(method_getTypeEncoding(method), encoding) != 0) {
        [NSException raise:@"UnavailableABI" format:@"%@ does not implement %s with expected ABI %s", receiver, name, encoding];
    }
    return selector;
}

static id leafIcon(id manager, NSString *identifier) {
    id model = objectMessage(manager, "iconModel");
    SEL selector = requireMethod(model, "leafIconForIdentifier:", "@24@0:8@16");
    return ((id (*)(id, SEL, id))objc_msgSend)(model, selector, identifier);
}

static id validatedWidgetIcon(id manager, NSDictionary *command, NSMutableDictionary *response) {
    NSString *identifier = requiredString(command, @"iconIdentifier");
    NSString *widgetIdentifier = requiredString(command, @"widgetIdentifier");
    id icon = leafIcon(manager, identifier);
    Class widgetClass = NSClassFromString(@"SBWidgetIcon");
    if (!icon || !widgetClass || ![icon isKindOfClass:widgetClass]) {
        [NSException raise:@"MissingWidgetIcon" format:@"No concrete widget icon for %@", identifier];
    }
    SEL isWidget = requireMethod(icon, "isWidgetIcon", "B16@0:8");
    SEL isStack = requireMethod(icon, "isWidgetStackIcon", "B16@0:8");
    if (!((BOOL (*)(id, SEL))objc_msgSend)(icon, isWidget) || ((BOOL (*)(id, SEL))objc_msgSend)(icon, isStack)) {
        [NSException raise:@"UnsafeWidgetIcon" format:@"Target %@ is not an individual widget icon", identifier];
    }
    id widget = objectMessage(icon, "activeWidget");
    BOOL identityVerified = NO;
    if ([widget respondsToSelector:sel_registerName("uniqueIdentifier")]) {
        requireMethod(widget, "uniqueIdentifier", "@16@0:8");
        id actualIdentifier = objectMessage(widget, "uniqueIdentifier");
        if (![[actualIdentifier description] isEqual:widgetIdentifier]) {
            [NSException raise:@"WidgetIdentityMismatch" format:@"Target %@ widget UUID %@ differs from %@", identifier, actualIdentifier, widgetIdentifier];
        }
        identityVerified = YES;
    }
    response[@"iconIdentifier"] = identifier;
    response[@"widgetIdentifier"] = widgetIdentifier;
    response[@"iconClass"] = NSStringFromClass([icon class]);
    response[@"widgetIdentityVerified"] = @(identityVerified);
    return icon;
}

static id containingHomeList(id manager, id icon) {
    requireMethod(manager, "rootFolder", "@16@0:8");
    id root = objectMessage(manager, "rootFolder");
    SEL selector = requireMethod(root, "listContainingIcon:", "@24@0:8@16");
    id list = ((id (*)(id, SEL, id))objc_msgSend)(root, selector, icon);
    Class listClass = NSClassFromString(@"SBIconListModel");
    if (!list || !listClass || ![list isKindOfClass:listClass]) {
        [NSException raise:@"MissingHomeList" format:@"Widget does not belong to a concrete Home icon list"];
    }
    requireMethod(list, "moveContainedIcon:toIndex:options:", "v40@0:8@16Q24Q32");
    return list;
}

static void operateExistingWidget(NSDictionary *command, NSMutableDictionary *response) {
    id controller = objectMessage(NSClassFromString(@"SBIconController"), "sharedInstance");
    id manager = objectMessage(controller, "iconManager");
    id icon = validatedWidgetIcon(manager, command, response);
    if ([requiredString(command, @"mode") isEqual:@"remove"]) {
        SEL selector = requireMethod(manager, "removeIcon:options:undoActionName:completion:", "v48@0:8@16Q24@32@?40");
        ((void (*)(id, SEL, id, unsigned long long, id, id))objc_msgSend)(manager, selector, icon, 0, nil, nil);
        response[@"status"] = @"removal_submitted";
        response[@"action"] = @"remove";
    } else if ([requiredString(command, @"mode") isEqual:@"ensure"]) {
        SEL selector = requireMethod(manager, "revealIcon:animated:completionHandler:", "v36@0:8@16B24@?28");
        if (command[@"position"]) {
            if (![requiredString(command, @"position") isEqual:@"top"]) {
                [NSException raise:@"InvalidPosition" format:@"Only same-page top positioning is supported"];
            }
            id list = containingHomeList(manager, icon);
            SEL moveSelector = sel_registerName("moveContainedIcon:toIndex:options:");
            ((void (*)(id, SEL, id, unsigned long long, unsigned long long))objc_msgSend)(list, moveSelector, icon, 0, 0);
            response[@"position"] = @"top";
        }
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(manager, selector, icon, YES, nil);
        response[@"status"] = @"submitted";
        response[@"action"] = @"reveal";
        response[@"animated"] = @YES;
    } else {
        [NSException raise:@"InvalidCommand" format:@"Existing widget operation must be ensure or remove"];
    }
}

static NSNumber *widgetSizeClass(NSDictionary *command) {
    NSString *size = requiredString(command, @"size");
    NSNumber *sizeClass = @{@"small": @1, @"medium": @2, @"large": @3}[size];
    if (!sizeClass) {
        [NSException raise:@"InvalidSize" format:@"Unsupported size %@", size];
    }
    return sizeClass;
}

static id descriptorForWidget(id manager, NSDictionary *command, NSMutableDictionary *response) {
    NSString *kind = requiredString(command, @"kind");
    NSString *extension = requiredString(command, @"extension");
    NSString *size = requiredString(command, @"size");
    NSNumber *sizeClass = widgetSizeClass(command);
    id provider = objectMessage(manager, "widgetExtensionProvider");
    if (!provider) {
        [NSException raise:@"UnavailableProvider" format:@"SpringBoard widget provider is not initialized"];
    }
    id descriptors = objectMessage(provider, "sbh_descriptorsByExtensionIdentifier");
    id candidates = [descriptors objectForKey:extension];
    id descriptor = nil;
    NSUInteger matchingDescriptors = 0;
    if ([candidates conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id candidate in candidates) {
            if ([objectMessage(candidate, "kind") isEqual:kind]) {
                descriptor = candidate;
                matchingDescriptors++;
            }
        }
    }
    if (matchingDescriptors > 1) {
        [NSException raise:@"DuplicateDescriptors" format:@"Multiple installed descriptors for %@ / %@", extension, kind];
    }
    if (!descriptor && command[@"container"]) {
        NSString *container = requiredString(command, @"container");
        SEL selector = sel_registerName("sbh_descriptorWithKind:extensionBundleIdentifier:containerBundleIdentifier:");
        if (![provider respondsToSelector:selector]) {
            [NSException raise:@"UnavailableSelector" format:@"Widget provider lacks container descriptor lookup"];
        }
        descriptor = ((id (*)(id, SEL, id, id, id))objc_msgSend)(provider, selector, kind, extension, container);
    }
    if (!descriptor) {
        [NSException raise:@"MissingDescriptor" format:@"No installed descriptor for %@ / %@", extension, kind];
    }
    if (![objectMessage(descriptor, "kind") isEqual:kind]) {
        [NSException raise:@"DescriptorMismatch" format:@"Installed descriptor does not match kind %@", kind];
    }
    SEL supportedSelector = sel_registerName("supportedFamilies");
    if (![descriptor respondsToSelector:supportedSelector]) {
        [NSException raise:@"UnavailableSelector" format:@"Descriptor lacks supportedFamilies"];
    }
    unsigned long supportedFamilies = ((unsigned long (*)(id, SEL))objc_msgSend)(descriptor, supportedSelector);
    if (!(supportedFamilies & (1UL << sizeClass.unsignedLongValue))) {
        [NSException raise:@"UnsupportedFamily" format:@"%@ does not support %@ (mask %lu)", kind, size, supportedFamilies];
    }
    if (![manager respondsToSelector:sel_registerName("_ensureWidgetIsVisibleForDebuggingWithDescriptor:sizeClass:")]) {
        [NSException raise:@"UnavailableSelector" format:@"Widget manager lacks ensure placement selector"];
    }
    response[@"descriptor"] = [descriptor description];
    return descriptor;
}

static void submitWidget(NSDictionary *command, NSMutableDictionary *response) {
    if (![requiredString(command, @"mode") isEqualToString:@"ensure"]) {
        [NSException raise:@"InvalidCommand" format:@"Only ensure commands are supported"];
    }
    id controller = objectMessage(NSClassFromString(@"SBIconController"), "sharedInstance");
    id manager = objectMessage(controller, "iconManager");
    id descriptor = descriptorForWidget(manager, command, response);
    NSNumber *sizeClass = widgetSizeClass(command);
    SEL selector = sel_registerName("_ensureWidgetIsVisibleForDebuggingWithDescriptor:sizeClass:");
    ((void (*)(id, SEL, id, long))objc_msgSend)(manager, selector, descriptor, sizeClass.longValue);
    response[@"status"] = @"submitted";
}

static void validateExistingWidgets(NSDictionary *command, NSMutableDictionary *response) {
    id targets = command[@"targets"];
    if (![targets isKindOfClass:NSArray.class] || ![targets count]) {
        [NSException raise:@"InvalidCommand" format:@"Validation requires a nonempty target array"];
    }
    id controller = objectMessage(NSClassFromString(@"SBIconController"), "sharedInstance");
    id manager = objectMessage(controller, "iconManager");
    id desired = command[@"desired"];
    if (![desired isKindOfClass:NSDictionary.class]) {
        [NSException raise:@"InvalidCommand" format:@"Validation requires the desired widget descriptor"];
    }
    NSMutableDictionary *desiredDetails = [desired mutableCopy];
    descriptorForWidget(manager, desired, desiredDetails);
    response[@"desired"] = desiredDetails;
    NSMutableArray *validated = NSMutableArray.array;
    for (id target in targets) {
        if (![target isKindOfClass:NSDictionary.class]) {
            [NSException raise:@"InvalidCommand" format:@"Each validation target must be an identifier dictionary"];
        }
        NSMutableDictionary *details = NSMutableDictionary.dictionary;
        id icon = validatedWidgetIcon(manager, target, details);
        if ([command[@"position"] isEqual:@"top"]) containingHomeList(manager, icon);
        [validated addObject:details];
    }
    response[@"targets"] = validated;
    response[@"status"] = @"validated";
}

static NSString *intentString(id intent, const char *name) {
    requireMethod(intent, name, "@16@0:8");
    id value = objectMessage(intent, name);
    if (![value isKindOfClass:NSString.class] || ![value length]) {
        [NSException raise:@"UnsupportedIntentIdentifier" format:@"%s did not return a nonempty string", name];
    }
    return value;
}

static NSDictionary *canonicalIntent(id intent) {
    Class intentClass = NSClassFromString(@"INAppIntent");
    if (!intentClass || ![intent isMemberOfClass:intentClass]) {
        [NSException raise:@"UnsupportedIntentClass" format:@"Configuration requires concrete INAppIntent"];
    }
    requireMethod(intent, "serializedParameters", "@16@0:8");
    id parameters = objectMessage(intent, "serializedParameters");
    if (![parameters isKindOfClass:NSDictionary.class] || ![NSJSONSerialization isValidJSONObject:parameters]) {
        [NSException raise:@"UnsupportedParameters" format:@"serializedParameters must be a JSON-valid dictionary"];
    }
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:nil];
    parameters = [NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil];
    if (![parameters isKindOfClass:NSDictionary.class]) {
        [NSException raise:@"InvalidParameterSnapshot" format:@"Cannot detach the full canonical parameter dictionary"];
    }
    return @{@"intentClass": NSStringFromClass([intent class]),
             @"appBundleIdentifier": intentString(intent, "_intents_bundleIdForLaunching"),
             @"extensionBundleIdentifier": intentString(intent, "extensionBundleId"),
             @"appIntentIdentifier": intentString(intent, "appIntentIdentifier"),
             @"parameters": parameters};
}

static NSData *canonicalJSON(id value) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:&error];
    if (!data) [NSException raise:@"InvalidCanonicalJSON" format:@"%@", error];
    return data;
}

typedef id __attribute__((ns_returns_retained)) (*IntentInitializer)(id __attribute__((ns_consumed)), SEL, id, id, id, id);

static id reconstructedIntent(NSDictionary *configuration) {
    Class intentClass = NSClassFromString(@"INAppIntent");
    id allocated = [intentClass alloc];
    SEL selector = requireMethod(allocated, "initWithAppBundleIdentifier:extensionBundleIdentifier:appIntentIdentifier:serializedParameters:", "@48@0:8@16@24@32@40");
    id result = ((IntentInitializer)objc_msgSend)(allocated, selector,
        configuration[@"appBundleIdentifier"], configuration[@"extensionBundleIdentifier"],
        configuration[@"appIntentIdentifier"], configuration[@"parameters"]);
    if (!result) [NSException raise:@"ReconstructionFailed" format:@"INAppIntent initializer returned nil"];
    return result;
}

static void exportConfiguration(NSDictionary *command, NSMutableDictionary *response) {
    id controller = objectMessage(NSClassFromString(@"SBIconController"), "sharedInstance");
    id manager = objectMessage(controller, "iconManager");
    id icon = validatedWidgetIcon(manager, command, response);
    id widget = objectMessage(icon, "activeWidget");
    SEL selector = requireMethod(manager, "intentForWidget:ofIcon:", "@32@0:8@16@24");
    id intent = ((id (*)(id, SEL, id, id))objc_msgSend)(manager, selector, widget, icon);
    NSDictionary *current = canonicalIntent(intent);
    if (![current[@"extensionBundleIdentifier"] isEqual:requiredString(command, @"extension")] ||
        ![current[@"appBundleIdentifier"] isEqual:requiredString(command, @"container")]) {
        [NSException raise:@"ConfigurationIdentityMismatch" format:@"Live intent application/extension differs from persisted widget"];
    }
    NSDictionary *candidate = current;
    BOOL apply = [requiredString(command, @"mode") isEqual:@"applyConfiguration"];
    if (apply) {
        id envelope = command[@"configuration"];
        if (![envelope isKindOfClass:NSDictionary.class]) {
            [NSException raise:@"InvalidConfiguration" format:@"Configuration envelope must be a dictionary"];
        }
        for (NSString *key in @[@"udid", @"extension", @"container", @"kind", @"size", @"iconIdentifier", @"widgetIdentifier"]) {
            if (![envelope[key] isEqual:command[key]]) {
                [NSException raise:@"ConfigurationTargetMismatch" format:@"Configuration %@ differs from current target", key];
            }
        }
        candidate = envelope[@"intent"];
        if (![candidate isKindOfClass:NSDictionary.class] || ![candidate[@"parameters"] isKindOfClass:NSDictionary.class] ||
            ![NSJSONSerialization isValidJSONObject:candidate[@"parameters"]]) {
            [NSException raise:@"InvalidConfiguration" format:@"Configuration intent/parameters must be JSON-valid dictionaries"];
        }
        for (NSString *key in @[@"intentClass", @"appBundleIdentifier", @"extensionBundleIdentifier", @"appIntentIdentifier"]) {
            if (![candidate[key] isEqual:current[key]]) {
                [NSException raise:@"ConfigurationIntentMismatch" format:@"Configuration %@ differs from current intent", key];
            }
        }
        if ([candidate count] != 5 || ![envelope[@"schemaVersion"] isEqual:@1]) {
            [NSException raise:@"InvalidConfiguration" format:@"Configuration requires the full schemaVersion 1 canonical intent"];
        }
    }
    id detached = reconstructedIntent(candidate);
    NSDictionary *roundtrip = canonicalIntent(detached);
    if (![canonicalJSON(roundtrip) isEqual:canonicalJSON(candidate)]) {
        [NSException raise:@"RoundtripMismatch" format:@"Detached reconstruction changed canonical IDs or parameters"];
    }
    if (apply) {
        SEL update = requireMethod(manager, "_handleUpdatedConfiguration:forDataSource:ofIcon:archiving:", "v44@0:8@16@24@32B40");
        requireMethod(icon, "activeWidget", "@16@0:8");
        requireMethod(widget, "uniqueIdentifier", "@16@0:8");
        ((void (*)(id, SEL, id, id, id, BOOL))objc_msgSend)(manager, update, detached, widget, icon, YES);
        id updatedWidget = objectMessage(icon, "activeWidget");
        requireMethod(updatedWidget, "uniqueIdentifier", "@16@0:8");
        id updatedIdentifier = objectMessage(updatedWidget, "uniqueIdentifier");
        if (![updatedIdentifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:updatedIdentifier]) {
            [NSException raise:@"InvalidUpdatedIdentity" format:@"Updated active widget has no UUID"];
        }
        NSMutableDictionary *readbackCommand = [command mutableCopy];
        readbackCommand[@"mode"] = @"exportConfiguration";
        readbackCommand[@"widgetIdentifier"] = updatedIdentifier;
        exportConfiguration(readbackCommand, response);
        if (![canonicalJSON(response[@"configuration"][@"intent"]) isEqual:canonicalJSON(candidate)]) {
            [NSException raise:@"ConfigurationReadbackMismatch" format:@"Updated live intent differs from requested full canonical intent"];
        }
        response[@"widgetIdentifier"] = command[@"widgetIdentifier"];
        response[@"appliedWidgetIdentifier"] = updatedIdentifier;
        response[@"status"] = @"configuration_applied";
        response[@"archiving"] = @YES;
        return;
    }
    NSMutableDictionary *envelope = [@{@"schemaVersion": @1, @"intent": current} mutableCopy];
    for (NSString *key in @[@"udid", @"extension", @"container", @"kind", @"size", @"iconIdentifier", @"widgetIdentifier"]) {
        envelope[key] = requiredString(command, key);
    }
    response[@"configuration"] = envelope;
    response[@"roundtripVerified"] = @YES;
    response[@"roundtrip"] = roundtrip;
    NSMutableDictionary *identifiers = NSMutableDictionary.dictionary;
    for (NSString *name in @[@"identifier", @"intentId"]) {
        SEL getter = sel_registerName(name.UTF8String);
        if ([intent respondsToSelector:getter]) {
            requireMethod(intent, name.UTF8String, "@16@0:8");
            id value = objectMessage(intent, name.UTF8String);
            if (value) identifiers[name] = [value description];
        }
    }
    response[@"observedIdentifiers"] = identifiers;
    NSMutableDictionary *representations = NSMutableDictionary.dictionary;
    SEL plistSelector = sel_registerName("widgetPlistableRepresentation:");
    if ([intent respondsToSelector:plistSelector]) {
        requireMethod(intent, "widgetPlistableRepresentation:", "@24@0:8^@16");
        NSError *error = nil;
        id plist = ((id (*)(id, SEL, NSError *__autoreleasing *))objc_msgSend)(intent, plistSelector, &error);
        NSMutableDictionary *details = NSMutableDictionary.dictionary;
        if (plist) {
            details[@"class"] = NSStringFromClass([plist class]);
            details[@"jsonValid"] = @([NSJSONSerialization isValidJSONObject:plist]);
            if ([NSJSONSerialization isValidJSONObject:plist]) details[@"value"] = plist;
        }
        if (error) details[@"error"] = error.description;
        representations[@"widgetPlistableRepresentation"] = details;
    }
    SEL jsonSelector = sel_registerName("_JSONDictionaryRepresentationWithConfiguration:");
    if ([intent respondsToSelector:jsonSelector]) {
        requireMethod(intent, "_JSONDictionaryRepresentationWithConfiguration:", "@24@0:8@16");
        id value = ((id (*)(id, SEL, id))objc_msgSend)(intent, jsonSelector, nil);
        if (value) {
            NSMutableDictionary *details = [@{@"class": NSStringFromClass([value class]), @"jsonValid": @([NSJSONSerialization isValidJSONObject:value])} mutableCopy];
            if ([NSJSONSerialization isValidJSONObject:value]) details[@"value"] = value;
            representations[@"JSONDictionaryRepresentation"] = details;
        }
    }
    response[@"representations"] = representations;
    response[@"status"] = @"configuration_exported";
}

static NSArray *relevantMethods(Class inspectedClass, BOOL includeIcons) {
    NSMutableArray *methods = NSMutableArray.array;
    NSArray *terms = includeIcons
        ? @[@"widget", @"delete", @"remove", @"reveal", @"visible", @"scroll", @"model", @"list", @"icon", @"identifier", @"kind", @"extension", @"bundle", @"size", @"descriptor", @"folder", @"position", @"index", @"path", @"intent", @"configuration", @"archive", @"update", @"cache", @"save"]
        : @[@"widget", @"delete", @"remove", @"reveal", @"visible", @"scroll", @"model", @"list", @"folder", @"position", @"index", @"path", @"intent", @"configuration", @"archive", @"update", @"cache", @"save"];
    for (Class current = inspectedClass; current && current != NSObject.class; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *entries = class_copyMethodList(current, &count);
        for (unsigned int index = 0; index < count; index++) {
            NSString *selector = NSStringFromSelector(method_getName(entries[index]));
            BOOL relevant = NO;
            for (NSString *term in terms) {
                if ([selector rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    relevant = YES;
                    break;
                }
            }
            if (relevant) {
                [methods addObject:@{@"class": NSStringFromClass(current), @"selector": selector,
                                     @"encoding": [NSString stringWithUTF8String:method_getTypeEncoding(entries[index])]}];
            }
        }
        free(entries);
    }
    [methods sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"selector" ascending:YES]]];
    return methods;
}

static id optionalObjectGetter(id receiver, const char *name) {
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod([receiver class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != '@') return nil;
    return objectMessage(receiver, name);
}

static NSDictionary *inspectObject(id object) {
    return @{@"class": NSStringFromClass([object class]), @"methods": relevantMethods([object class], YES),
             @"description": [object description]};
}

static void inspectRuntime(NSDictionary *command, NSMutableDictionary *response) {
    id controller = objectMessage(NSClassFromString(@"SBIconController"), "sharedInstance");
    id manager = objectMessage(controller, "iconManager");
    NSMutableDictionary *inspection = NSMutableDictionary.dictionary;
    inspection[@"iconManagerClass"] = NSStringFromClass([manager class]);
    inspection[@"iconManagerMethods"] = relevantMethods([manager class], NO);
    if ([manager respondsToSelector:sel_registerName("iconModel")]) {
        id model = objectMessage(manager, "iconModel");
        if (model) {
            inspection[@"iconModelClass"] = NSStringFromClass([model class]);
            inspection[@"iconModelMethods"] = relevantMethods([model class], YES);
        }
    }
    NSMutableDictionary *rootFolders = NSMutableDictionary.dictionary;
    id managerRoot = optionalObjectGetter(manager, "rootFolder");
    if (managerRoot) rootFolders[@"iconManager.rootFolder"] = inspectObject(managerRoot);
    id model = optionalObjectGetter(manager, "iconModel");
    id modelRoot = optionalObjectGetter(model, "rootFolder");
    if (modelRoot) rootFolders[@"iconModel.rootFolder"] = inspectObject(modelRoot);
    inspection[@"rootFolders"] = rootFolders;
    NSMutableDictionary *classes = NSMutableDictionary.dictionary;
    for (NSString *name in @[@"SBIconController", @"SBHIconManager", @"SBIconModel", @"SBWidgetIcon", @"SBHWidgetIcon", @"SBIconListModel", @"SBIconListView", @"SBRootFolder", @"SBFolder", @"CHSIntentReference"]) {
        Class inspectedClass = NSClassFromString(name);
        if (inspectedClass) classes[name] = relevantMethods(inspectedClass, YES);
    }
    if (command[@"iconIdentifier"]) {
        id icon = leafIcon(manager, requiredString(command, @"iconIdentifier"));
        if (icon) {
            inspection[@"targetIconClass"] = NSStringFromClass([icon class]);
            inspection[@"targetIconMethods"] = relevantMethods([icon class], YES);
            inspection[@"targetIconDescription"] = [icon description];
            id folder = optionalObjectGetter(icon, "folder");
            if (folder) inspection[@"targetIconFolder"] = inspectObject(folder);
            if ([icon respondsToSelector:sel_registerName("activeWidget")]) {
                id widget = objectMessage(icon, "activeWidget");
                if (widget) {
                    inspection[@"targetWidgetClass"] = NSStringFromClass([widget class]);
                    inspection[@"targetWidgetMethods"] = relevantMethods([widget class], YES);
                    inspection[@"targetWidgetDescription"] = [widget description];
                    SEL intentSelector = sel_registerName("intentForWidget:ofIcon:");
                    if ([manager respondsToSelector:intentSelector]) {
                        requireMethod(manager, "intentForWidget:ofIcon:", "@32@0:8@16@24");
                        id intent = ((id (*)(id, SEL, id, id))objc_msgSend)(manager, intentSelector, widget, icon);
                        if (intent) {
                            inspection[@"targetIntent"] = inspectObject(intent);
                        } else {
                            inspection[@"targetIntentMissing"] = @YES;
                        }
                    } else {
                        inspection[@"targetIntentUnavailable"] = @YES;
                    }
                }
            }
        } else {
            inspection[@"targetIconMissing"] = @YES;
        }
    }
    inspection[@"classes"] = classes;
    response[@"inspection"] = inspection;
    response[@"status"] = @"inspected";
}

static void tick(NSString *directory, NSString *udid, NSString *identity) {
    @autoreleasepool {
        BOOL ready = NO;
        @try {
            id controller = objectMessage(NSClassFromString(@"SBIconController"), "sharedInstance");
            id manager = objectMessage(controller, "iconManager");
            ready = objectMessage(manager, "widgetExtensionProvider") != nil;
        } @catch (NSException *exception) {
            ready = NO;
        }
        saveJSON(@{@"pid": @(getpid()), @"timestamp": @([NSDate.date timeIntervalSince1970]),
                   @"udid": udid, @"identity": identity, @"protocol": @1, @"ready": @(ready)},
                 [directory stringByAppendingPathComponent:@"heartbeat.json"]);
        NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"command.json"]];
        if (!data || !ready) return;
        id command = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![command isKindOfClass:NSDictionary.class]) return;
        static NSString *lastNonce = nil;
        id nonce = command[@"nonce"];
        if (![nonce isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:nonce] || [lastNonce isEqual:nonce]) return;
        lastNonce = [nonce copy];
        double started = CFAbsoluteTimeGetCurrent();
        NSMutableDictionary *response = [@{@"nonce": nonce, @"pid": @(getpid()), @"status": @"error"} mutableCopy];
        @try {
            if ([command[@"mode"] isEqual:@"exportConfiguration"] || [command[@"mode"] isEqual:@"applyConfiguration"]) {
                exportConfiguration(command, response);
            } else if ([requiredString(command, @"mode") isEqualToString:@"validate"]) {
                validateExistingWidgets(command, response);
            } else if ([requiredString(command, @"mode") isEqualToString:@"inspect"]) {
                inspectRuntime(command, response);
            } else if (command[@"iconIdentifier"]) {
                operateExistingWidget(command, response);
            } else {
                submitWidget(command, response);
            }
        } @catch (NSException *exception) {
            response[@"status"] = @"error";
            response[@"error"] = exception.description;
        }
        response[@"callMilliseconds"] = @((CFAbsoluteTimeGetCurrent() - started) * 1000);
        saveJSON(response, [directory stringByAppendingPathComponent:@"response.json"]);
    }
}

__attribute__((constructor)) static void startWorker(void) {
    @autoreleasepool {
        const char *rawDirectory = getenv("WIDGETCTL_SESSION_DIR");
        const char *rawIdentity = getenv("WIDGETCTL_IDENTITY");
        const char *rawUDID = getenv("WIDGETCTL_UDID");
        if (!rawDirectory || !rawIdentity || !rawUDID) return;
        NSString *directory = [NSString stringWithUTF8String:rawDirectory];
        NSString *identity = [NSString stringWithUTF8String:rawIdentity];
        NSString *udid = [NSString stringWithUTF8String:rawUDID];
        if (![directory.lastPathComponent isEqual:udid] || ![[NSUUID alloc] initWithUUIDString:udid]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            static dispatch_source_t timer;
            timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), 200 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
            dispatch_source_set_event_handler(timer, ^{ tick(directory, udid, identity); });
            dispatch_resume(timer);
        });
    }
}
