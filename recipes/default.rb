# rubocop:disable LineLength
#
# Cookbook Name:: cabot
# Recipe:: default
#
# Copyright (C) 2014 Rafael Fonseca
#
# MIT License
#




# dependency setup
%w(git npm python redis build-essential postgresql::server database::postgresql).each do |cookbook|
  include_recipe cookbook
end

%w(ruby1.9.1 libpq-dev).each do |pkg|
  package pkg do
    action :install
  end
end

%w(coffee-script less).each do |pkg|
  npm_package pkg do
    action :install
  end
end

gem_package 'foreman' do
  action :install
end

{
  'Django' => '1.4.10', 'PyJWT' => '0.1.2', 'South' => '0.7.6', 'amqp' => '1.4.5', 'anyjson' => '0.3.3',
  'argparse' => '1.2.1', 'billiard' => '3.3.0.13', 'celery' => '3.1.7', 'distribute' => '0.6.24',
  'dj-database-url' => '0.2.2', 'django-appconf' => '0.6', 'django-celery' => '3.1.1',
  'django-celery-with-redis' => '3.0', 'django-compressor' => '1.2', 'django-jsonify' => '0.2.1',
  'django-mptt' => '0.6.0', 'django-polymorphic' => '0.5.3', 'django-redis' => '1.4.5', 'django-smtp-ssl' => '1.0',
  'gunicorn' => '18.0', 'hiredis' => '0.1.1', 'httplib2' => '0.7.7', 'icalendar' => '3.2', 'kombu' => '3.0.8',
  'mock' => '1.0.1', 'psycopg2' => '2.5.1', 'pytz' => '2013.9', 'redis' => '2.9.0', 'requests' => '0.14.2',
  'six' => '1.5.1', 'twilio' => '3.4.1', 'wsgiref' => '0.1.2', 'python-dateutil' => '2.1'
}.each do |mod, version|
  python_pip mod do
    action :install
    version version
  end
end

# user setup
group node[:cabot][:group]

user node[:cabot][:user] do
  supports manage_home: false
  home node[:cabot][:home_dir]
  group node[:cabot][:group]
  shell '/bin/bash'
end

directory node[:cabot][:home_dir] do
  action :create
  owner node[:cabot][:user]
  group node[:cabot][:group]
end

directory node[:cabot][:log_dir] do
  owner node[:cabot][:user]
  group node[:cabot][:group]
  mode 0775
end

# app deploy
git node[:cabot][:home_dir] do
  action :sync
  repository node[:cabot][:repo_url]
  user node[:cabot][:user]
  group node[:cabot][:group]
end

template "#{node[:cabot][:home_dir]}/conf/development.env" do
  action :create
  source 'production.env.erb'
  variables(
            debug: node[:cabot][:debug],
            database_url: node[:cabot][:database_url],
            port: node[:cabot][:port],
            virtualenv_dir: node[:cabot][:virtualenv_dir],
            admin_email: node[:cabot][:admin_email],
            from_email: node[:cabot][:from_email],
            ical_url: node[:cabot][:ical_url],
            celery_broker_url: node[:cabot][:celery_broker_url],
            django_secret_key: node[:cabot][:django_secret_key],
            graphite_api_url: node[:cabot][:graphite_api_url],
            graphite_username: node[:cabot][:graphite_username],
            graphite_password: node[:cabot][:graphite_password],
            hipchat_room_id: node[:cabot][:hipchat_room_id],
            hipchat_api_key: node[:cabot][:hipchat_api_key],
            jenkins_api_url: node[:cabot][:jenkins_api_url],
            jenkins_username: node[:cabot][:jenkins_username],
            jenkins_password: node[:cabot][:jenkins_password],
            smtp_host: node[:cabot][:smtp_host],
            smtp_username: node[:cabot][:smtp_username],
            smtp_password: node[:cabot][:smtp_password],
            smtp_port: node[:cabot][:smtp_port],
            twilio_account_sid: node[:cabot][:twilio_account_sid],
            twilio_auth_token: node[:cabot][:twilio_auth_token],
            twilio_outgoing_number: node[:cabot][:twilio_outgoing_number],
            www_http_host: node[:cabot][:www_http_host],
            www_scheme: node[:cabot][:www_scheme]
          )
end
username = "vagrant"

Chef::Log.debug("generate ssh skys for #{username}.")
  
execute "generate ssh" do
  user username
  creates "/home/#{username}/.ssh/id_rsa.pub"
  command "ssh-keygen -t rsa -q -f /home/#{username}/.ssh/id_rsa -P \"\""
end


bash 'setup' do
  cwd node[:cabot][:home_dir]
  code <<-EOH
    ssh-keygen 
    python setup.py install
    pip install setuptools --upgrade
    virtualenv venv
    chmod +x venv/bin/activate
    chmod +x venv/bin/activate.fish
    source venv/bin/activate; 
  EOH
end

postgresql_connection_info = {
  :host     => '127.0.0.1',
  :port     => node['postgresql']['config']['port'],
  :username => 'postgres',
  :password => node['postgresql']['password']['postgres']
}

database 'index' do
  connection postgresql_connection_info
  provider   Chef::Provider::Database::Postgresql
  action     :create
end

template "#{node[:cabot][:home_dir]}/createdjangosite.py.py" do
  source "createdjangosite.py.erb"
  action :create
end

template "#{node[:cabot][:home_dir]}/createdjangosuperuser.py" do
  source "createdjangosuperuser.py.erb"
  action :create
end

template "/etc/init.d/cabot" do
  source "cabot.systemd.erb"
  action :create
end




bash 'run migrations' do
  cwd node[:cabot][:home_dir]
  code <<-EOH
    source venv/bin/activate; cat createdjangosite.py | sudo foreman run python shell
    source venv/bin/activate; cat createdjangosite.py | sudo foreman run python shell
    source venv/bin/activate; sudo foreman run python manage.py syncdb 
    source venv/bin/activate; sudo foreman run python manage.py migrate cabotapp --noinput 
    source venv/bin/activate; sudo foreman run python manage.py migrate djcelery --noinput
    source venv/bin/activate; sudo foreman run python manage.py migrate --noinput

  EOH
end

bash 'collect static assets' do
  cwd node[:cabot][:home_dir]
  code <<-EOH
    source venv/bin/activate; sudo foreman run python manage.py collectstatic --noinput 
    source venv/bin/activate; sudo foreman run python manage.py compress --force
  EOH
end

python_pip "uwsgi" do
  action :install
end

directory "/etc/uwsgi" do
  action :create
end

directory "/etc/uwsgi/vassals" do
  action :create
end

template "/etc/systemd/system/uwsgi.service" do
  source "uwsgi.service.erb"
  action :create
end

template "/etc/uwsgi/vassals/cabot.ini" do
  source "cabot.ini.erb"
  action :create
end

template "/etc/systemd/system/cabot-worker.service" do
  source "cabot-worker.service.erb"
  action :create
end

user 'www' do
  system true
end

directory "/var/www/" do
  action :create
  owner "www"
  group "www"
end

directory "/var/www/logs" do
  action :create
  owner "www"
  group "www"
end

directory "/var/www/run" do
  action :create
  owner "www"
  group "www"
end

directory "/var/www/run/celery" do
  action :create
  owner "www"
  group "www"
end

service 'nginx' do
  supports :status => true, :restart => true, :reload => true
  action   :stop
end


include_recipe 'nginx'
include_recipe 'redisio'
include_recipe 'redisio::enable'

# template "/etc/nginx/conf.d/cabot.conf" do
#   source "cabot.conf.erb"
#   action :create
# end

# service 'cabot' do
#   provider Chef::Provider::Service::Init::Debian
#   action :nothing
# end

bash 'setup upstart' do
  cwd node[:cabot][:home_dir]
  code <<-EOH
    source venv/bin/activate; sudo foreman export systemd /etc/init.d -f #{node[:cabot][:home_dir]}/Procfile  -u #{node[:cabot][:user]} -a cabot -t #{node[:cabot][:home_dir]}/systemd
  EOH
end


