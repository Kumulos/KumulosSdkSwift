
Pod::Spec.new do |s|
  s.name = "KumulosSdkSwiftExtension"
  s.version = "10.0.0"
  s.license = "MIT"
  s.summary = "Official Swift SDK for integrating Kumulos services with your mobile apps"
  s.homepage = "https://github.com/Kumulos/KumulosSdkSwift"
  s.authors = { "Kumulos Ltd" => "support@kumulos.com" }
  s.source = { :git => "https://github.com/Kumulos/KumulosSdkSwift.git", :tag => "#{s.version}" }

  s.swift_version = "5.0"
  s.ios.deployment_target = "10.0"

  s.source_files = "Sources/ObjC/Extension/include/KumulosSDKExtension.h", "Sources/Extension/**/*.swift", "Sources/Shared/**/*.swift"
  s.exclude_files = "Carthage", "Sources/SDK"
  s.module_name = "KumulosSDKExtension"

end
