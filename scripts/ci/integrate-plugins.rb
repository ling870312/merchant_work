#!/usr/bin/env ruby
# 在瘦身 SDK 解压根目录执行（目录下有 HBuilder-Hello/ 与 SDK/）。
# 作用：把两个原生插件集成进 HBuilder-Hello 工程的 HBuilder target（xcodeproj 编辑）。
# 环境变量：IOS_BUNDLE_ID（由工作流从渠道 oem.json 动态注入，无默认明文值）
require 'pathname'
require 'xcodeproj'

bundle_id = ENV.fetch('IOS_BUNDLE_ID', '')
abort '!! IOS_BUNDLE_ID 未设置（应由工作流从渠道 oem.json 动态注入）' if bundle_id.empty?
proj_path = 'HBuilder-Hello/HBuilder-Hello.xcodeproj'

project = Xcodeproj::Project.open(proj_path)
# 用 product_type 找 app target，不依赖 target 名（SDK 工程实际 target 名是 HBuilder）
target = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' }
abort '!! app target not found（工程结构异常）' if target.nil?
puts "Target: #{target.name}"

main = project.main_group

# PlugIns group 建在 main 根，path 相对工程根指向 target 源码目录下的 PlugIns
# 工程根 = sdk-root/HBuilder-Hello/，target 源码目录 = sdk-root/HBuilder-Hello/HBuilder-Hello/
plugins = main.find_subpath('PlugIns', true)
plugins.path = 'HBuilder-Hello/PlugIns'

def add_sources(group, dir, target)
  added = 0
  return added unless File.directory?(dir)
  Dir.glob(File.join(dir, '*')).sort.each do |f|
    next if File.directory?(f)
    base = File.basename(f)
    next if group.files.any? { |x| x.path == base }
    ref = group.new_file(base)
    if base.end_with?('.m', '.mm')
      target.add_file_references([ref])
      added += 1
    end
  end
  added
end

# 1) Monitor-Player 源码进编译
mon = plugins.find_subpath('DoorMasterMonitorPlayer', true)
mon.path = 'DoorMasterMonitorPlayer'
n = add_sources(mon, 'HBuilder-Hello/HBuilder-Hello/PlugIns/DoorMasterMonitorPlayer', target)
puts "Monitor-Player: #{n} 个源文件加入编译"

# 1.5) MobileVLCKit 高级播放内核（H265/RTMP/FLV/WSS-FLV）。
# 由 prepare 工作流把 MobileVLCKit.xcframework 放置到 PlugIns/MobileVLCKit/。
# 存在则 Link + Embed（该 framework 是动态库，必须同时 embed），并加 FRAMEWORK_SEARCH_PATHS。
vlc_src_rel = 'HBuilder-Hello/HBuilder-Hello/PlugIns/MobileVLCKit'
vlc_xcframework = Dir.glob(File.join(vlc_src_rel, '*.xcframework')).first
if vlc_xcframework
  vlc = plugins.find_subpath('MobileVLCKit', true)
  vlc.path = 'MobileVLCKit'
  base = File.basename(vlc_xcframework)
  vlc_ref = vlc.files.find { |x| x.path == base } || vlc.new_file(base)
  # Link binary
  unless target.frameworks_build_phase.files.any? { |bf| bf.file_ref == vlc_ref }
    target.frameworks_build_phase.add_file_reference(vlc_ref)
  end
  # Embed Frameworks（动态库必须 embed 到产物）
  embed_phase = target.copy_files_build_phases.find do |p|
    p.name.to_s == 'Embed Frameworks' || p.dst_subfolder_spec.to_s == '10'
  end
  if embed_phase.nil?
    embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
    embed_phase.dst_subfolder_spec = '10'
  end
  unless embed_phase.files.any? { |bf| bf.file_ref == vlc_ref }
    embed_phase.add_file_reference(vlc_ref)
  end
  puts "MobileVLCKit: 已 Link+Embed #{base}"
else
  puts 'MobileVLCKit: PlugIns/MobileVLCKit 下未找到 .xcframework，跳过（H265/RTMP 高级流将不可用）'
end

# 2) TRTC framework Link + Embed，bundle 进 Resources
# 【暂不使用 TRTC】临时禁用，排除第三方 SDK 导致 INVALID_BINARY 的嫌疑。恢复时取消下方注释。
# trtc = plugins.find_subpath('TRTC', true)
# trtc.path = 'TRTC'
# frameworks = %w[TXLiteAVSDK_TRTC.framework DMTRTCSDK.framework]
# frameworks.each do |fw|
#   next if trtc.files.any? { |x| x.path == fw }
#   target.frameworks_build_phase.add_file_reference(trtc.new_file(fw))
# end
# embed_phase = target.copy_files_build_phases.find { |p| p.name.to_s == 'Embed Frameworks' || p.dst_subfolder_spec.to_s == '10' }
# if embed_phase.nil?
#   embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
#   embed_phase.dst_subfolder_spec = '10'
# end
# frameworks.each do |fw|
#   ref = trtc.files.find { |x| x.path == fw }
#   next if ref.nil?
#   next if embed_phase.files.any? { |bf| bf.file_ref == ref }
#   embed_phase.add_file_reference(ref)
# end
# unless trtc.files.any? { |x| x.path == 'dmtrtcresource.bundle' }
#   target.resources_build_phase.add_file_reference(trtc.new_file('dmtrtcresource.bundle'))
# end
# puts 'TRTC: framework Link+Embed + bundle Resources 完成'
puts 'TRTC 已禁用（暂不使用），未集成 framework'

# 3) 补系统库 AVKit/QuartzCore（工程已链 AVFoundation/CoreMedia/libresolv/libc++/Accelerate）
%w[AVKit QuartzCore].each do |fw|
  exists = target.frameworks_build_phase.files.any? do |bf|
    bf.file_ref && bf.file_ref.display_name == "#{fw}.framework"
  end
  next if exists
  ref = main.new_file("#{fw}.framework")
  ref.source_tree = 'SDKROOT'
  ref.path = "System/Library/Frameworks/#{fw}.framework"
  ref.last_known_file_type = 'wrapper.framework'
  target.frameworks_build_phase.add_file_reference(ref)
end
puts '系统库 AVKit/QuartzCore 已确保链接'

# 4) PrivacyInfo.xcprivacy
# SDK 4.87 工程的 project.pbxproj 同时注册了 SDK/PrivacyInfo.xcprivacy 和
# HBuilder-Hello/HBuilder-Hello/PrivacyInfo.xcprivacy 两个 Copy Bundle Resources 条目，
# Xcode 26 报 Multiple commands produce。保留 SDK 自带的那份（workflow 已覆盖内容），
# 从构建阶段和文件引用中移除 HBuilder-Hello 下的那份。
target.resources_build_phase.files.reject! do |bf|
  next false unless bf.file_ref
  path = bf.file_ref.real_path.to_s
  if path.include?('HBuilder-Hello/PrivacyInfo.xcprivacy') || path.include?('HBuilder-Hello/HBuilder-Hello/PrivacyInfo.xcprivacy')
    puts "移除构建引用: #{path}"
    true
  else
    false
  end
end
# 从 main group 中移除 HBuilder-Hello 下的 PrivacyInfo 文件引用
main.recursive_children.select do |x|
  x.is_a?(Xcodeproj::Project::Object::PBXFileReference) &&
    x.real_path.to_s.include?('HBuilder-Hello/PrivacyInfo.xcprivacy') &&
    !x.real_path.to_s.include?('SDK')
end.each do |ref|
  puts "移除文件引用: #{ref.real_path}"
  ref.remove_from_project
end

# 5) build settings
# 自动定位真实 DCloud 头 DCUniModule.h 所在目录，加入 HEADER_SEARCH_PATHS。
# 目的：让 DMMonitorPlayerModule 等插件源码编译时命中真实 DCUniModule.h，
# 使 UNI_EXPORT_METHOD 真正生效（否则回落 DMMonitorPluginCompat.h 桩实现，
# 方法不会注册到 uni 运行时，JS 端 requireNativePlugin 拿到空对象 methods: none）。
#
# Xcode 工程在 HBuilder-Hello/HBuilder-Hello.xcodeproj，所以
#   $(PROJECT_DIR) = $(SRCROOT) = sdk-root/HBuilder-Hello
# DCUniModule.h 通常在 SDK/ 目录下（sdk-root/SDK/...），在 PROJECT_DIR 之外，
# 因此必须用 $(SRCROOT)/.. 回到 sdk-root 再拼接，而不能直接 reject 掉。
project_dir_real = File.expand_path('HBuilder-Hello')
sdk_root_real = File.expand_path('.')
dcmodule_hdrs = Dir.glob(File.join('HBuilder-Hello', '**', 'DCUniModule.h'))
  .concat(Dir.glob(File.join('SDK', '**', 'DCUniModule.h')))
  .concat(Dir.glob(File.join('**', 'DCUniModule.h')))
dcmodule_dirs = dcmodule_hdrs
  .map { |hdr| File.dirname(File.expand_path(hdr)) }
  .uniq

header_search = dcmodule_dirs.map do |dir|
  rel_to_project = Pathname.new(dir).relative_path_from(Pathname.new(project_dir_real)).to_s
  if rel_to_project.start_with?('..')
    # 路径在 PROJECT_DIR 之外（如 SDK/ 目录），用 $(SRCROOT)/.. 回到 sdk-root
    rel_to_sdkroot = Pathname.new(dir).relative_path_from(Pathname.new(sdk_root_real)).to_s
    "$(SRCROOT)/../#{rel_to_sdkroot}"
  else
    "$(PROJECT_DIR)/#{rel_to_project}"
  end
end

if header_search.empty?
  puts 'DCUniModule.h: 未定位到真实头，插件将回退 DMMonitorPluginCompat 兼容桩'
  puts "DCUniModule.h: 搜索范围 HBuilder-Hello/**/*.h + SDK/**/*.h + **/*.h"
  puts "DCUniModule.h: sdk-root = #{sdk_root_real}"
  puts "DCUniModule.h: project_dir = #{project_dir_real}"
else
  puts "DCUniModule.h: 命中真实头，HEADER_SEARCH_PATHS += #{header_search.inspect}"
end

# MobileVLCKit.xcframework 所在目录，供链接器搜索（ld: framework not found）
framework_search = []
framework_search << '$(SRCROOT)/HBuilder-Hello/PlugIns/MobileVLCKit' if vlc_xcframework

target.build_configurations.each do |c|
  # Xcode 26 最低支持的 iOS 部署目标为 15.0（低于此值 xcodebuild 会直接报错）
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  # 仅 iPhone：关闭 iPad 支持，App Store Connect 不再要求 iPad 截屏
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  c.build_settings['ARCHS'] = 'arm64'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id

  unless header_search.empty?
    hsp = c.build_settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
    hsp = hsp.is_a?(Array) ? hsp.dup : [hsp]
    hsp |= header_search
    c.build_settings['HEADER_SEARCH_PATHS'] = hsp
  end

  unless framework_search.empty?
    fsp = c.build_settings['FRAMEWORK_SEARCH_PATHS'] || ['$(inherited)']
    fsp = fsp.is_a?(Array) ? fsp.dup : [fsp]
    fsp |= framework_search
    c.build_settings['FRAMEWORK_SEARCH_PATHS'] = fsp
  end
end

project.save
puts '✅ xcodeproj 集成完成并保存'
