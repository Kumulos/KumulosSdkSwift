### Description of Changes

(briefly outline the reason for changes, and describe what's been done)

### Breaking Changes

-   None

### Release Checklist

Prepare:

-   [ ] Detail any breaking changes. Breaking changes require a new major version number
-   [ ] Check `pod lib lint` passes

Bump versions in:

-   [ ] `Sources/Kumulos.swift`
-   [ ] `KumulosSdkSwift.podspec`
-   [ ] `KumulosSdkSwiftExtension.podspec`
-   [ ] `Build target version for plist`
-   [ ] `README.md`

Release:

-   [ ] Squash and merge to master
-   [ ] Delete branch once merged
-   [ ] Create tag from master matching chosen version
-   [ ] Run `pod trunk push` to publish to CocoaPods

Post Release:

Update docs site with correct version number references

- [ ] https://docs.kumulos.com/developer-guide/sdk-reference/swift/
- [ ] https://docs.kumulos.com/getting-started/integrate-app/

Update changelog:

- [ ] https://docs.kumulos.com/developer-guide/sdk-reference/swift/#changelog
