
Pod::Spec.new do |s|
  s.name = "KumulosSdkSwift"
  s.version = "2.0.0"
  s.license = "MIT"
  s.summary = "Official Swift SDK for integrating Kumulos services with your mobile apps"
  s.homepage = "https://github.com/Kumulos/KumulosSdkSwift"
  s.authors = { "Kumulos Ltd" => "support@kumulos.com" }
  s.source = { :git => "https://github.com/Kumulos/KumulosSdkSwift.git", :tag => "#{s.version}" }

  s.ios.deployment_target = "9.0"

  s.source_files = "Sources"
  s.exclude_files = "Carthage"
  s.module_name = "KumulosSDK"

  s.framework = "Alamofire"

  s.dependency "Alamofire", "~> 4.4.0"
  s.dependency "kstenerud/KSCrash" "~> 1.15.12"
end
