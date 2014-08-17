VM project defines
  VM_NAME
    required

  BUILD_ID
    optional
    defaults to ENV['BUILD_NUMBER'] || 'dev'

  TEMPLATE
    optional
    defaults to 'Templates/c65.medium'

  TEMPLATE_CI_FOLDER
    optional
    defaults to 'Template CI'

  TEMPLATE_RELEASE_FOLDER
    optional
    defaults to 'RallyVM_Vapp'

  ANNOTATION
    optional, if given value is appended to default
    defaults to [#{VM_NAME}-#{BUILD_ID}]



Rake Tasks

lint
  checks VM project ENV params
  checks chef credentials
  checks vmware credentials

build
  fails with 'run rake clean' if VM or test VM exist

  success => 
    VM template in CI folder
    test VM in a running state in CI folder

  failure => 
    possibly a VM in an unknown state
    possibly a test VM in an unknown state

test
  runs specs on test VM

clean 
  deletes VM in CI folder if exists
  deletes test VM in CI folder if exists

release:clean
  deletes -lastSuccessfulBuild VM
  deletes -lastTested VM

release => [release:clean]
  renames VM template to -lastSuccessfulBuild and moves to release folder
  renames test VM template to -lastTested

release:failed:clean
  deletes -lastFailedBuild VM
  deletes -lastTested VM

release:failed => [release:failed:clean]
  renames VM template to -lastFailedBuild
  renames test VM template to -lastTested

ci
  begin
    execute [clean, build, test, release]
  rescue e
    execute [release:failed]
    fail e
  end






Other thoughts...


Vmfile
ENV       'VM_NAME', 'onprem-orcavm'
ENV       'BUILD_ID',   'dev'

FROM      'Templates/c65.medium'
TO        'Template CI/#{VM_NAME}-#{BUILD_ID}'
CPU       2, 1
MEMORYMB  2048
DISK      20480, ...
DISK      40960, ...
CUST_SPEC 'bld-config'
POWERON
RUN!      'touch /tmp/it'
RUN       'rake cook'
SHUTDOWN
TEMPLATE

FROM     'Template CI/#{VM_NAME}-#{BUILD_ID}'
TO       'Template CI/#{VM_NAME}-#{BUILD_ID}-test'
RUN      'rake test'

RELEASE 'Template CI/#{VM_NAME}-#{BUILD_ID}',      'OnPremVappCI/#{VM_NAME}'
RELEASE 'Template CI/#{VM_NAME}-#{BUILD_ID}-test', 'Template CI/#{VM_NAME}-#{BUILD_ID}-lastTested'

FAIL
RELEASE 'Template CI/#{VM_NAME}-#{BUILD_ID}',      'Template CI/#{VM_NAME}-#{BUILD_ID}-lastFailed'
RELEASE 'Template CI/#{VM_NAME}-#{BUILD_ID}-test', 'Template CI/#{VM_NAME}-#{BUILD_ID}-lastTested'

