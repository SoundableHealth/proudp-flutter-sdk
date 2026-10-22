#
# Used only when the app has Swift Package Manager disabled.
# Run `pod lib lint soundable_proudp.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'soundable_proudp'
  s.version          = '1.0.0'
  s.summary          = 'Soundable Health proudP SDK for Flutter.'
  s.description      = <<-DESC
Records voiding sound, uploads it to the Soundable Health server and returns the analysis result.
                       DESC
  s.homepage         = 'https://github.com/SoundableHealth/proudp-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Soundable Health' => 'dev@soundable.health' }
  s.source           = { :path => '.' }
  # SoundableProudpLib is not published to CocoaPods, so a copy of it is compiled into this pod.
  s.source_files = 'soundable_proudp/Sources/soundable_proudp/**/*.swift', 'Classes/SoundableProudpLib/**/*.swift'
  s.resource_bundles = { 'soundable_proudp_privacy' => ['soundable_proudp/Sources/soundable_proudp/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
