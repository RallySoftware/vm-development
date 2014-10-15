# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vm/development/version'

Gem::Specification.new do |spec|
  spec.name          = 'vm-development'
  spec.version       = Vm::Development::VERSION
  spec.authors       = ['Brian Dupras']
  spec.email         = ['bdupras@rallydev.com']
  spec.summary       = %q{Rally Software Development Corp VM development}
  spec.description   = %q{Rally Software Development Corp VM development}
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'

  spec.add_dependency 'mixlib-shellout', '~> 1.4'
  spec.add_dependency 'rspec-its', '~>1.0.1'
  spec.add_dependency 'serverspec', '~>2.0'
  spec.add_dependency 'chef', '~>11.12'
  spec.add_dependency 'chef-vault', '~>2.1'
  spec.add_dependency 'knife-solo', '~> 0.4'
  spec.add_dependency 'berkshelf', '3.1.1'
  spec.add_dependency 'vmonkey', '~> 0.10.0.pre'
end
