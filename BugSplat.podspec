Pod::Spec.new do |s|
  s.name         = 'BugSplat'
  s.version      = '2.0.0'
  s.summary      = 'BugSplat crash reporting for iOS, macOS, and tvOS'
  s.description  = <<-DESC
    BugSplat is a crash reporting SDK for Apple platforms (iOS, macOS, tvOS).
    It provides automatic crash reporting with PLCrashReporter statically linked.
  DESC
  s.homepage     = 'https://github.com/BugSplat-Git/bugsplat-apple'
  s.license      = { type: 'MIT' }
  s.author       = { 'BugSplat' => 'support@bugsplat.com' }
  s.source       = { http: 'https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v2.0.0/BugSplat.xcframework.zip' }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.5'
  s.tvos.deployment_target = '13.0'

  s.static_framework = true
  s.vendored_frameworks = 'BugSplat.xcframework'
  s.libraries = 'z', 'c++'
end
