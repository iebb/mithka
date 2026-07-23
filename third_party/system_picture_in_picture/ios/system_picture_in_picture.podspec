Pod::Spec.new do |s|
  s.name             = 'system_picture_in_picture'
  s.version          = '0.1.0'
  s.summary          = 'Mithka system Picture-in-Picture Flutter plugin.'
  s.description      = <<-DESC
Mithka's included native Picture-in-Picture implementation.
                       DESC
  s.homepage         = 'https://github.com/nekoko-inc/mithka'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Nekoko' => 'dev@nekoko.it' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.frameworks       = 'AVFoundation', 'AVKit'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
