import hashlib
import json
import subprocess


SDKS = ('iphoneos', 'iphonesimulator', 'watchos', 'watchsimulator')


def cache_toolchain():
    def output(*arguments):
        return subprocess.check_output(arguments, text=True).strip()

    identity = {'xcode': output('xcodebuild', '-version')}
    identity.update({sdk: output('xcrun', '--sdk', sdk, '--show-sdk-build-version')
                     for sdk in SDKS})
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


if __name__ == '__main__':
    print(cache_toolchain())
