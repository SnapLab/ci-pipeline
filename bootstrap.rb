#!/usr/bin/env ruby

require 'yaml'
require 'json'
require 'json-schema'
require 'rest-client'
require 'deep_merge'
require "base64"

CONFIG_DIR = 'config'
JSON_SCHEMA = 'schema.json'
CONSUL = ENV['CONSUL']
VAULT = ENV['VAULT']
VAULT_TOKEN = ENV['VAULT_TOKEN']
OPTION_FILE = 'option.json'
ENV_FILE = 'env'

def init(path)
  option_data = Hash.new
  Dir.foreach(path) do |file|
    if MIME::Types.type_for(file).to_s =~ /(text|application)\/(x-)?yaml/
      file_data = YAML.load_file("#{CONFIG_DIR}/#{file}")
      if JSON::Validator.validate!(JSON_SCHEMA, JSON.dump(file_data), {:validate_schema => true, :strict => true})
        consul_add("#{file_data['namespace']}/#{file_data['name']}/_", file_data['scm'])
        env_data = []
        file_data['environments'].each { |env|
          consul_add("#{file_data['namespace']}/#{file_data['name']}/#{env['environment']}",  JSON.dump(env))
          env_data += [ env['environment'] ]
        }
      end
      option_data.deep_merge!({ file_data['namespace'] => { file_data['name'] => env_data }})
    end
  end
  save_option(option_data)
end

def consul_add(path, data)
  puts "#{CONSUL}/#{path}"
  RestClient.put("#{CONSUL}/#{path}", data)
end

def consul_get(path)
  return RestClient.get("#{CONSUL}/#{path}")
end

def vault_get(path)
  return RestClient.get(
    "#{VAULT}/#{path}",
    headers = {'X-Vault-Token': VAULT_TOKEN}
  )
end

def save_option(data)
  File.write(OPTION_FILE, JSON.dump(data))
end

def save_env(team, project, env)
  resp = JSON.parse(consul_get("#{team}/#{project}/#{env}")).pop
  if resp.include?('Value')
    File.open(ENV_FILE, 'w') {|file| file.truncate(0) }
    data = JSON.parse(Base64.decode64(resp['Value']))
    secrets = JSON.parse(vault_get("#{team}/#{project}/#{env}"))['data']
    data['vars'].each { |var|
      var.each { |k,v|
        File.open(ENV_FILE, 'a') { |file|
          file.puts "#{k}=#{v}"
        }
      }
    }
    secrets.each { |k,v|
      unless k.eql?("") || v.eql?("")
        File.open(ENV_FILE, 'a') { |file|
          file.puts "#{k}=#{v}"
        }
      end
    }
  end
end

def main(args)
  team, project, env = args
  if team.nil? || project.nil? || env.nil?
    init(CONFIG_DIR)
  else
    save_env(team, project, env)
  end
end

main(ARGV)