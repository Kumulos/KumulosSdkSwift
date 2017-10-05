# Kumulos Swift SDK [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

Kumulos provides tools to build and host backend storage for apps, send push notifications, view audience and behavior analytics, and report on adoption, engagement and performance.

Select an installation method below to get started.

## Get Started with CocoaPods

Add the following line to your app's target in your `Podfile`:

```
pod 'KumulosSdkSwift', '~> 2.0'
```

Run `pod install` to install your dependencies.

After installation, you can now import & initialize the SDK with:

```swift
import KumulosSDK

Kumulos.initialize("YOUR_API_KEY", secretKey: "YOUR_SECRET_KEY")
```

For more information on integrating the Swift SDK with your project, please see the [Kumulos Swift integration guide](https://docs.kumulos.com/integration/swift).

## Get Started with Carthage

Add the following line to your `Cartfile`:

```
github "Kumulos/KumulosSdkSwift" ~> 2.0
```

Run `carthage update` to install your dependencies then follow the [Carthage integration steps](https://github.com/Carthage/Carthage#getting-started) to link the framework with your project.

After installation, you can now import & initialize the SDK with:

```swift
import KumulosSDK

Kumulos.initialize("YOUR_API_KEY", secretKey: "YOUR_SECRET_KEY")
```

For more information on integrating the Swift SDK with your project, please see the [Kumulos Swift integration guide](https://docs.kumulos.com/integration/swift).

## Contributing

Pull requests are welcome for any improvements you might wish to make. If it's something big and you're not sure about it yet, we'd be happy to discuss it first. You can either file an issue or drop us a line to [support@kumulos.com](mailto:support@kumulos.com).

## License

This project is licensed under the MIT license with portions licensed under the BSD 2-Clause license. See our LICENSE file and individual source files for more information.

## Requirements

- iOS9+
- Swift3
