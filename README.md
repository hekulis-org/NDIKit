
## Initial Setup Steps

Copy the libraries:
`cp -R /Library/NDI\ SDK\ for\ Apple/lib/{iOS,macOS} Vendor/NDI-SDK/lib/`

Copy the headers:
`cp -R /Library/NDI\ SDK\ for\ Apple/include/* Vendor/NDI-SDK/include/`

## Usage
`./Scripts/build-xcframework.sh`
`swift build`
`swift test`

## TODO
- min os versions should be variables in the build script
- change development team in example apps

- simulator support
- script to refresh sdk files and rebuild framework
- hello world
- fill out wrapper stuff.
