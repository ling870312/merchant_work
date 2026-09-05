#!/usr/bin/env ruby
# 诊断：用 App Store Connect API 查询 laiyima 应用的构建与审核状态
# 环境变量：ASC_API_KEY_ID / ASC_ISSUER_ID / ASC_API_KEY_P8（.p8 文件路径）/ BUNDLE_ID
require 'openssl'
require 'json'
require 'base64'
require 'time'
require 'net/http'

def b64(data)
  Base64.urlsafe_encode64(data).delete('=')
end

# 1) 生成 JWT（ES256，raw r||s 签名）
key = OpenSSL::PKey.read(File.read(ENV['P8_FILE']))
header = { alg: 'ES256', kid: ENV['ASC_API_KEY_ID'], typ: 'JWT' }
payload = { iss: ENV['ASC_ISSUER_ID'], exp: Time.now.to_i + 1200, aud: 'appstoreconnect-v1' }
signing_input = "#{b64(header.to_json)}.#{b64(payload.to_json)}"
der = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
asn1 = OpenSSL::ASN1.decode(der)
r = asn1.value[0].value.to_s(2).rjust(32, "\x00")
s = asn1.value[1].value.to_s(2).rjust(32, "\x00")
sig = r + s
JWT = "#{signing_input}.#{b64(sig)}"

def api_get(path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{JWT}"
  req['Accept'] = 'application/json'
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  JSON.parse(res.body)
end

bundle_id = ENV['BUNDLE_ID']
abort '!! BUNDLE_ID 未设置（应由工作流从渠道 Secret 注入）' if bundle_id.nil? || bundle_id.empty?

# 2) 列出该 key 可见的所有 app，按 bundleId 精确匹配
puts "=== 该 API Key 可访问的 App 列表 ==="
apps_all = api_get('/v1/apps?limit=50')
target = nil
if apps_all['data'].nil? || apps_all['data'].empty?
  puts '⚠️ 无 app 访问权限，原始响应:'
  puts JSON.pretty_generate(apps_all)[0, 800]
else
  apps_all['data'].each do |a|
    bid = a.dig('attributes', 'bundleId')
    name = a.dig('attributes', 'name')
    mark = (bid == bundle_id ? '  <<< 目标' : '')
    puts "  #{a['id']} | #{bid} | #{name}#{mark}"
    target = a if bid == bundle_id
  end
end

target = apps_all['data'][0] if target.nil? && apps_all['data']&.size == 1
if target.nil?
  puts "\n⚠️ 未找到 bundleId=#{bundle_id} 的 app，改用第一个可见 app 继续"
  target = apps_all['data'][0]
end
app_id = target['id']
puts "\n目标 App: #{target.dig('attributes','name')} (#{target.dig('attributes','bundleId')}) id=#{app_id}"

# 3) 查最近 10 个构建的完整状态
builds = api_get("/v1/builds?filter[app]=#{app_id}&sort=-uploadedDate&limit=10")
puts "\n=== 最近构建（上传处理状态） ==="
if builds['data'].nil? || builds['data'].empty?
  puts '⚠️ 无构建记录'
else
  builds['data'].each do |b|
    a = b['attributes']
    puts "  version=#{a['version']} build=#{a['buildNumber'] || '?'} processingState=#{a['processingState']} uploaded=#{a['uploadedDate']}"
  end
end

# 4) 查 App Store 审核状态（关键：INVALID_BINARY / REJECTED 等）
puts "\n=== App Store 版本审核状态 ==="
begin
  versions = api_get("/v1/apps/#{app_id}/appStoreVersions?limit=10")
  if versions['data'].nil? || versions['data'].empty?
    puts '⚠️ 无 App Store 版本记录'
  else
    versions['data'].each do |v|
      a = v['attributes']
      puts "  versionString=#{a['versionString']} appStoreState=#{a['appStoreState']} state=#{a['state'] || '?'}"
    end
  end
rescue => e
  puts "查询 appStoreVersions 失败: #{e.message}"
end

# 5) 查最近构建的 beta 详情
puts "\n=== BuildBetaDetail（TestFlight 状态） ==="
(builds['data'] || []).first(3).each do |b|
  id = b['id']
  ver = b['attributes']['version']
  detail = api_get("/v1/builds/#{id}/relationships/buildBetaDetail")
  detail_id = detail.dig('data', 'id')
  if detail_id
    d = api_get("/v1/buildBetaDetails/#{detail_id}")
    attrs = d.dig('data', 'attributes') || {}
    puts "  #{ver}: internal=#{attrs['internalBuildState']}, external=#{attrs['externalBuildState']}"
  end
end

# 6) 打印完整构建 JSON 供人工排查（前 2 个）
puts "\n=== 最近 2 个构建完整 attributes（供排查） ==="
(builds['data'] || []).first(2).each do |b|
  puts JSON.pretty_generate(b['attributes'] || {})
  puts '---'
end
