build:
    swift build

test:
    swift test

bundle: build
    ./scripts/bundle-app.sh

run: bundle
    open .build/debug-bundle/MacUML.app

clean:
    swift package clean

release-build:
    swift build -c release

release-bundle: release-build
    ./scripts/bundle-app.sh release
