require "spaceship"
require 'json'

puts "开始登录..."

Spaceship.login

puts "登录完成"

def create_group(group_id, name)
    group = Spaceship::Portal.app_group.find(group_id)
    unless group
        group = Spaceship::Portal.app_group.create!(group_id: group_id, name: name)
    end
    return group
end

def create_app(group, bundle_id, name, capabilities)
    # Create a new app
    app = Spaceship::Portal.app.find(bundle_id)
    unless app
        app = Spaceship::Portal.app.create!(bundle_id: bundle_id, name: name)
    end
    puts " app: #{app.bundle_id}, #{app.name}"

    # update app services
    capabilities.each do |item|
        case item
        when "health_kit"
            app = app.update_service(Spaceship::Portal.app_service.health_kit.on)
        when "app_group"
            app = app.update_service(Spaceship::Portal.app_service.app_group.on)
        when "push_notification"
            app = app.update_service(Spaceship::Portal.app_service.push_notification.on)
        when "access_wifi"
            app = app.update_service(Spaceship::Portal.app_service.access_wifi.on)
        when "associated_domains"
            app = app.update_service(Spaceship::Portal.app_service.associated_domains.on)
        when "nfc_tag_reading"
            app = app.update_service(Spaceship::Portal.app_service.nfc_tag_reading.on)
        else
            puts "  unknown service: #{item}"
        end
    end

    # associate app with group
    if capabilities.include?("app_group")
        app = app.associate_groups([group])
    end

    puts "  enable_services: #{app.enable_services}"

    return app
end

def create_provisioning_profile(app, mobileprovision)
    # development
    development_provisioning_profile(app, mobileprovision)

    # adhoc
    adhoc_provisioning_profile(app, mobileprovision)
end

def development_provisioning_profile(app, mobileprovision)
    # Create a new development provisioning profile
    filtered_profiles = Spaceship::Portal.provisioning_profile.development.find_by_bundle_id(bundle_id: app.bundle_id)
    profile = nil
    if filtered_profiles.length > 0 
        exist_profile = filtered_profiles[0]
        dev_certs = Spaceship::Portal.certificate.development.all
        exist_profile.certificates = dev_certs
        profile = exist_profile.update!
    else
        all_devices = Spaceship::Portal.device.all
        provisionNameDev = mobileprovision + '_dev'
        dev_certs = Spaceship::Portal.certificate.development.all
        profile = Spaceship::Portal.provisioning_profile.development.create!(bundle_id: app.bundle_id, certificate: dev_certs, name: provisionNameDev, devices: all_devices)
    end
    puts "  development profile: #{profile.name} #{profile.id}"

    # Download profile
    download_profile(profile)
end

def adhoc_provisioning_profile(app, mobileprovision)
    # Create a new adhoc provisioning profile
    filtered_profiles = Spaceship::Portal.provisioning_profile.ad_hoc.find_by_bundle_id(bundle_id: app.bundle_id)
    profile = nil
    if filtered_profiles.length > 0 
        exist_profile = filtered_profiles[0]
        dis_cert = Spaceship::Portal.certificate.production.all.sort { |a, b| a.expires <=> b.expires }.last
        exist_profile.certificates = [ dis_cert]
        profile = exist_profile.update!
    else
        all_devices = Spaceship::Portal.device.all
        provisionNameAdhoc = mobileprovision + '_adhoc'
        dis_cert = Spaceship::Portal.certificate.production.all.sort { |a, b| a.expires <=> b.expires }.last
        profile = Spaceship::Portal.provisioning_profile.ad_hoc.create!(bundle_id: app.bundle_id, certificate: [ dis_cert ], name: provisionNameAdhoc, devices: all_devices)
    end
    puts "  adhoc profile: #{profile.name} #{profile.id}"

    # Download profile
    download_profile(profile)
end

def download_profile(profile)
    # 判断 profiles 目录是否存在，不存在则创建
    Dir.mkdir('profiles') unless File.exists?('profiles')
    # 下载到 profiles 目录下
    mobileprovision_filename = profile.name + '.mobileprovision'
    File.write('profiles/' + mobileprovision_filename, profile.download)
end

def create_device(udid, name, status)
    device = Spaceship::Portal.device.find_by_udid(udid, include_disabled: true)
    # 如果device不存在则创建，如果status为disabled就不需要创建
    unless device
        return if status == 'disabled'
        device = Spaceship::Portal.device.create!(name: name, udid: udid)
    else
        if status == 'enabled'
            device.enable!
        else
            device.disable!
        end
    end
end

all_devices = JSON.load(File.open('devices.json'))
all_devices.each do |item1|
    puts "device: #{item1['name']} #{item1['udid']}"
    create_device(item1['udid'], item1['name'], item1['status'])
end
puts "==============================================================="

all_apps = JSON.load(File.open('apps.json'))
all_apps.each do |item1|
    apps = item1['apps']
    group = create_group(item1['group_id'], item1['name'])
    puts "group: #{group.name}"

    apps.each do |item2|
        capabilities = item2['capabilities']
        app = create_app(group, item2['bundle_id'], item2['name'], capabilities)

        provisioning_profile_name = item2['mobileprovision']
        create_provisioning_profile(app, provisioning_profile_name)
    end
    puts "-------------------------------------------------------------"
end