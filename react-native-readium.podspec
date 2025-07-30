require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "@sfenton/react-native-readium-with-cfi"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "13.0" }
  s.ios.deployment_target = "13.0"

  s.source       = { :git => "http://github.com/sfenton/react-native-readium.git", :tag => "#{s.version}" }
  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.swift_version = "5.0"

  s.dependency "React-Core"
  s.dependency "R2Shared"
  s.dependency "R2Streamer"
  s.dependency "R2Navigator"
  s.dependency "ReadiumInternal"
  s.dependency "GCDWebServer"
  s.dependency "ReadiumAdapterGCDWebServer"
end
