Pod::Spec.new do |s|
  s.name = 'mithka_proxy'
  s.version = '0.1.0'
  s.summary = 'App-scoped WebView proxy configuration for Mithka.'
  s.homepage = 'https://github.com/iebb/mithka'
  s.license = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author = { 'Mithka' => 'https://github.com/iebb/mithka' }
  s.source = { :path => '.' }
  s.source_files = 'mithka_proxy/Sources/mithka_proxy/**/*.swift'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.swift_version = '5.0'
  s.frameworks = 'WebKit', 'Network'
end
