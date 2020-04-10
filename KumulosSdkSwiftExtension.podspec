
Pod::Spec.new do |s|
  s.name = "KumulosSdkSwiftExtension"
  s.version = "8.4.1"
  s.license = "MIT"
  s.summary = "Official Swift SDK for integrating Kumulos services with your mobile apps"
  s.homepage = "https://github.com/Kumulos/KumulosSdkSwift"
  s.authors = { "Kumulos Ltd" => "support@kumulos.com" }
  s.source = { :git => "https://github.com/Kumulos/KumulosSdkSwift.git", :tag => "#{s.version}" }

  s.swift_version = "5.0"
  s.ios.deployment_target = "10.0"

  s.source_files = "Sources/Extension/**/*.{h,m,swift}", "Sources/Shared/**/*.{h,m,swift}"
  s.exclude_files = "Carthage"
  s.module_name = "KumulosSDKExtension"

end
