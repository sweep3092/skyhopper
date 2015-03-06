#
# Copyright (c) 2013-2015 SKYARCH NETWORKS INC.
#
# This software is released under the MIT License.
#
# http://opensource.org/licenses/mit-license.php
#

require 'pathname'
require "json"

class ChefServer::Deployment
  PackageURL   = "https://web-dl.packagecloud.io/chef/stable/packages/el/6/chef-server-core-12.0.1-1.x86_64.rpm".freeze
  TemplatePath = Rails.root.join("lib/cf_templates/chef_server.json").freeze
  EC2User      = "ec2-user".freeze

  # TODO: receive from controller
  User     = 'skyhopper'.freeze
  FullName = 'anakin skyhopper'.freeze
  EMail    = 'skyhopper@example.com'.freeze
  PassWord = 'ilikerandompasswords'.freeze

  Org      = 'skyarch'.freeze
  FullOrg  = 'Skyarch Networks Inc.'.freeze

  # TODO: Refactor
  Progress = {
    creating_infra: {percentage:  10, status: :in_progress},
    creating_stack: {percentage:  20, status: :in_progress},
    init_ec2:       {percentage:  40, status: :in_progress},
    install_chef:   {percentage:  60, status: :in_progress},
    setting_chef:   {percentage:  80, status: :in_progress},
    complete:       {percentage: 100, status: :complete},
    error:          {percentage: nil, status: :error}
  }.freeze


  class << self
    # chef_serverを作成し、自身のインスタンスを返す。
    # blockが与えられていれば、そのブロックに進捗状況を渡して実行する。
    def create(stack_name, region, keypair_name, keypair_value, &block)
      __yield :creating_infra, &block

      prj = Project.for_chef_server
      infra = Infrastructure.create_with_ec2_private_key(
        project_id:    prj.id,
        stack_name:    stack_name,
        keypair_name:  keypair_name,
        keypair_value: keypair_value,
        region:        region
      )

      #TODO: jsでバインドする前に投げちゃって拾えない＞＜；だから直したい
      __yield :creating_stack, &block

      stack = create_stack(infra)


      wait_creation(stack)

      physical_id = stack.instances.first.physical_resource_id
      chef_server = self.new(infra, physical_id)

      __yield :init_ec2, &block

      chef_server.wait_init_ec2


      __yield :install_chef, &block

      chef_server.fix_hostname
      chef_server.install_chef

      __yield :setting_chef, &block

      chef_server.init_knife_rb


      return chef_server

    rescue => ex
      Rails.logger.error(ex.message)
      __yield :error, ex.message, &block
      raise ex
    end


    # XXX: こぴぺをやめてここじゃないとこにちゃんと定義する
    def create_zabbix(stack_name, region, keypair_name, keypair_value)
      prj = Project.for_zabbix_server
      infra = Infrastructure.create_with_ec2_private_key(
        project:       prj,
        stack_name:    stack_name,
        keypair_name:  keypair_name,
        keypair_value: keypair_value,
        region:        region
      )
      stack = create_stack(infra)
      wait_creation(stack)

      physical_id = stack.instances.first.physical_resource_id
      server = self.new(infra, physical_id)
      server.wait_init_ec2
      set = AppSetting.get
      set.zabbix_fqdn = infra.ec2.instances[physical_id].public_dns_name
      set.save!
    end

    private

    def create_stack(infra, name = 'Chef Server')
      template = File.read(TemplatePath)

      cf_template = CfTemplate.new(
        infrastructure_id: infra.id,
        name:              name,
        detail:            "#{name} auto generated",
        value:             template
      )
      cf_template.create_cfparams_set(infra)
      cf_template.update_cfparams
      cf_template.save!

      s = Stack.new(infra)
      s.create(template, cf_template.parsed_cfparams)

      return s
    end

    def wait_creation(stack)
      stack.wait_status("CREATE_COMPLETE")
    end

    def __yield(data, msg = nil, &block)
      block.call(data, msg) if block
    end
  end

  def initialize(infra, physical_id)
    @infra = infra
    @physical_id = physical_id
  end

  def fqdn
    @fqdn ||= @infra.ec2.instances[@physical_id].public_dns_name
  end

  def ip_addr
    @ip_addr ||= @infra.ec2.instances[@physical_id].ip_address
  end

  def url
    "https://#{fqdn}/organizations/#{Org}"
  end

  def wait_init_ec2
    loop do
      begin
        exec_ssh(timeout: 5){}
      rescue
        sleep 10
        next
      else
        break
      end
    end
  end

  def fix_hostname
    exec_ssh do |ssh|
      ssh.shell do |sh|
        sh.execute! "sudo hostname #{fqdn}"
        sh.execute! %!sudo sed -i -E "s/^HOSTNAME=.+$/HOSTNAME=#{fqdn}/g" /etc/sysconfig/network!
        sh.execute! 'sudo service network restart'
        sh.close!
        sh.execute! 'exit'
      end
    end
  end

  def install_chef
    log = -> (process) { process.on_output{|pr, data| Rails.logger.debug("sh out > #{data}")} }

    exec_ssh do |ssh|
      ssh.shell do |sh|
        sh.execute! 'cd /tmp/'
        sh.execute! "sudo rpm -Uvh #{PackageURL}"
        sh.execute! 'sudo chef-server-ctl reconfigure'
        sh.execute! 'sudo chef-server-ctl start'
        # XXX: 1回目の user-create が何故か Internal Server Error でコケるので、2回やる。(とても闇)
        Rails.logger.debug("exec user-create")
        sh.execute! "sudo chef-server-ctl user-create #{User} #{FullName} #{EMail} #{PassWord} --filename #{User}.pem", &log
        Rails.logger.debug("exec user-create 2")
        sh.execute! "sudo chef-server-ctl user-create #{User} #{FullName} #{EMail} #{PassWord} --filename #{User}.pem", &log
        Rails.logger.debug("exec org-create")
        sh.execute! "sudo chef-server-ctl org-create #{Org} #{FullOrg} --association_user #{User} --filename #{Org}.pem", &log
        Rails.logger.debug("done")
        sh.close!
        sh.execute! 'exit'
      end
    end
  end

  def init_knife_rb
    admin_pem     = ''
    validator_pem = ''
    crt = ''

    exec_ssh do |ssh|
      ssh.shell do |sh|
        sh.execute! 'cd /tmp/'

        sh.execute!("sudo cat #{User}.pem") do |process|
          process.on_output do |pr, data|
            admin_pem = data
          end
        end

        sh.execute!("sudo cat #{Org}.pem") do |process|
          process.on_output do |pr, data|
            validator_pem = data
          end
        end

        sh.execute!("sudo cat /var/opt/opscode/nginx/ca/#{fqdn}.crt") do |process|
          process.on_output do |pr, data|
            crt = data
          end
        end

        sh.close!
        sh.execute! 'exit'
      end
    end

    # TODO: 直接~/.chef/下に鍵を作る path = Pathname.new(File.expand_path('~/.chef/'))
    #       開発環境で上書きされないようにするのはどうする?
    path = Rails.root.join('tmp', 'chef')
    FileUtils.mkdir_p(path) unless Dir.exists?(path)

    File.open(path.join("#{User}.pem"), 'w', 0600) do |f|
      f.write(admin_pem)
      f.flush
    end

    File.open(path.join("#{Org}.pem"), 'w', 0600) do |f|
      f.write(validator_pem)
      f.flush
    end

    crt_path = path.join('trusted_certs')
    Dir.mkdir(crt_path) unless Dir.exists?(crt_path)
    File.open(crt_path.join("#{fqdn}.crt"), 'w') do |f|
      f.write(crt)
      f.flush
    end

    File.open(path.join('knife.rb'), 'w') do |f|
      f.write <<-EOF
log_level                :info
log_location             STDOUT
node_name                '#{User}'
client_key               '~/.chef/#{User}.pem'
validation_client_name   '#{Org}-validator'
validation_key           '~/.chef/#{Org}.pem'
chef_server_url          '#{url}'
syntax_check_cache_path  '/home/#{EC2User}/.chef/syntax_check_cache'
      EOF
    end
  end

  def key
    return File.read(Rails.root.join('tmp', 'chef', "#{User}.pem"))
  end


  private

  def exec_ssh(opt = {}, &block)
    Net::SSH.start(fqdn, EC2User, {key_data: [@infra.ec2_private_key.value]}.merge(opt), &block)
  end
end
