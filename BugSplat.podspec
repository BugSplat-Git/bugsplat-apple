Pod::Spec.new do |s|
  s.name         = 'BugSplat'
  s.version      = '9.0.0'
  s.summary      = 'BugSplat crash, hang, error and feedback reporting for macOS, iOS and tvOS'
  s.description  = <<-DESC
    BugSplat 9 is a Swift API over bugsplat-native, BugSplat's cross-platform crash reporter built
    on Crashpad. On macOS capture, the dialog and the upload run out of process (BugSplatMonitor,
    BugSplatReporter.app); on iOS and tvOS capture is in process and reports are sent at the next launch.
  DESC
  s.homepage     = 'https://github.com/BugSplat-Git/bugsplat-apple'
  s.license      = { type: 'MIT', file: 'LICENSE.txt' }
  s.author       = { 'BugSplat' => 'support@bugsplat.com' }
  s.source       = { git: 'https://github.com/BugSplat-Git/bugsplat-apple.git', tag: s.version.to_s }

  s.swift_versions = ['5.9']
  s.osx.deployment_target = '13.0'
  s.ios.deployment_target = '15.0'
  s.tvos.deployment_target = '15.0'

  s.source_files = 'Sources/BugSplat/**/*.swift'
  s.resource_bundles = { 'BugSplat_BugSplat' => ['Sources/BugSplat/Resources/**/*'] }

  # The native framework is a release asset, fetched at install time.
  s.prepare_command = <<-CMD
    curl -sSL -o BugSplatNative.xcframework.zip "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/#{s.version}/BugSplatNative.xcframework.zip"
    rm -rf Frameworks && mkdir -p Frameworks && unzip -q BugSplatNative.xcframework.zip -d Frameworks
  CMD
  s.vendored_frameworks = 'Frameworks/BugSplatNative.xcframework'
  s.frameworks = 'Foundation', 'Security', 'CoreGraphics', 'CoreText'
  s.osx.frameworks = 'AppKit', 'IOKit'
  s.ios.frameworks = 'UIKit'
  s.tvos.frameworks = 'UIKit'
  s.libraries = 'c++', 'z'
  s.osx.libraries = 'bsm'
end
