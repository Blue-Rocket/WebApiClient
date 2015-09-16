Pod::Spec.new do |s|

  s.name         = 'WebApiClient'
  s.version      = '0.9.0'
  s.summary      = 'A HTTP client API based on configured routes.'

  s.description        = <<-DESC
                         WebApiClient provides a protocol-based HTTP client API based on configured routes with
                         support for object mapping for transforming requests and responses between native objects
                         and serialized forms, such as JSON. A full implementation of the API is also provided,
                         based on AFNetworking.
                         DESC

  s.homepage           = 'https://github.com/Blue-Rocket/WebApiClient'
  s.license            = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author             = { 'Matt Magoffin' => 'matt@bluerocket.us' }
  s.social_media_url   = 'http://twitter.com/bluerocketinc'
  s.platform           = :ios, '8.0'
  s.source             = { :git => 'https://github.com/Blue-Rocket/WebApiClient.git',
                           :tag => s.version.to_s }
  
  s.requires_arc       = true

  s.default_subspecs = 'All'
  
  s.subspec 'All' do |sp|
    sp.dependency 'WebApiClient/WebApiClient-Core'
	sp.dependency 'WebApiClient/WebApiClient-AFNetworking'
	sp.dependency 'WebApiClient/WebApiClient-Cache'
    sp.dependency 'WebApiClient/WebApiClient-RestKit'
  end
  
  s.subspec 'WebApiClient-Core' do |sp|
    sp.source_files = 'WebApiClient/Code/WebApiClient-Core.h', 'WebApiClient/Code/WebApiClient'
    #sp.dependency 'WebApiClient/Core'
	sp.dependency 'MAObjCRuntime', '~> 0.0.1'
	sp.dependency 'SOCKit',        '~> 1.1'
  end

  s.subspec 'WebApiClient-AFNetworking' do |sp|
    sp.source_files = 'WebApiClient/Code/WebApiClient-AFNetworking.h', 'WebApiClient/Code/WebApiClient-AFNetworking'
    sp.dependency 'WebApiClient/WebApiClient-Core'
    sp.dependency 'AFNetworking/NSURLSession', '~> 2.5'
  end

  s.subspec 'WebApiClient-Cache' do |sp|
    sp.source_files = 'WebApiClient/Code/WebApiClient-Cache.h', 'WebApiClient/Code/WebApiClient-Cache'
    sp.dependency 'WebApiClient/WebApiClient-Core'
    sp.dependency 'PINCache', '~> 2.0'
  end

  s.subspec 'WebApiClient-RestKit' do |sp|
    sp.source_files = 'WebApiClient/Code/WebApiClient-RestKit.h', 'WebApiClient/Code/WebApiClient-RestKit'
    sp.dependency 'WebApiClient/WebApiClient-Core'
    sp.dependency 'RestKit/ObjectMapping', '~> 0.24'
    sp.dependency 'TransformerKit/String', '~> 0.5'
  end

end
