#!/usr/bin/env ruby
# 仅用于 Simulator 构建（真机/IPA 工作流不调用本脚本）。
#
# 瘦身 SDK 里的部分 .a / .framework 只有真机切片（LC_BUILD_VERSION platform=2），
# Xcode 链接 Simulator 时会报：
#   "building for 'iOS-simulator', but linking in object file ... built for 'iOS'"
# 本脚本把 arm64 真机 Mach-O 的 platform 从 iOS(2) 改为 iOS Simulator(7)，
# 不改任何代码/符号，仅绕过链接器的平台校验。正式 IPA 不受影响。
#
# 兼容三种容器：
#   1. 普通 ar 静态库（!<arch>\n）
#   2. lipo 生成的 fat 静态库（0xcafebabe + 多个 ar 切片）
#   3. framework 内的 Mach-O（thin 或 fat）

LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2
PLATFORM_IOS_SIMULATOR = 7
AR_MAGIC = "!<arch>\n".b
FAT_MAGIC = 0xcafebabe

$stats = Hash.new(0)

def patch_thin_macho!(data)
  magic = data[0, 4] && data[0, 4].unpack1('V')
  return 0 unless [0xfeedfacf, 0xfeedface].include?(magic)

  is64 = magic == 0xfeedfacf
  header_size = is64 ? 32 : 28
  ncmds = data[16, 4].to_s.unpack1('V').to_i
  sizeofcmds = data[20, 4].to_s.unpack1('V').to_i
  off = header_size
  changed = 0

  while ncmds.positive?
    cmd = data[off, 4].to_s.unpack1('V').to_i
    cmdsize = data[off + 4, 4].to_s.unpack1('V').to_i
    break if cmdsize < 8 || off + cmdsize > header_size + sizeofcmds

    if cmd == LC_BUILD_VERSION
      platform = data[off + 8, 4].to_s.unpack1('V').to_i
      if platform == PLATFORM_IOS
        data[off + 8, 4] = [PLATFORM_IOS_SIMULATOR].pack('V')
        changed += 1
      end
      off += cmdsize
    elsif cmd == LC_VERSION_MIN_IPHONEOS
      # 旧格式没有 platform 字段（不存在 iOS Simulator 版本），
      # 直接删除该 load command，让链接器按目标平台处理。
      region_end = header_size + sizeofcmds
      data[off...(region_end - cmdsize)] = data[(off + cmdsize)...region_end]
      data[(region_end - cmdsize)...region_end] = "\0" * cmdsize
      sizeofcmds -= cmdsize
      ncmds -= 1
      data[16, 4] = [ncmds].pack('V')
      data[20, 4] = [sizeofcmds].pack('V')
      $stats[:version_min_removed] += 1
      changed += 1
      # 后面的命令已经左移，off 保持不变
    else
      off += cmdsize
    end
  end

  changed
end

def patch_macho_bytes!(data)
  changed = 0
  if data[0, 4] && data[0, 4].unpack1('N') == FAT_MAGIC
    nfat = data[4, 4].to_s.unpack1('N').to_i
    nfat.times do |i|
      base = 8 + i * 20
      off = data[base + 8, 4].to_s.unpack1('N').to_i
      size = data[base + 12, 4].to_s.unpack1('N').to_i
      next if off <= 0 || size <= 0 || off + size > data.bytesize
      slice = data[off, size]
      changed += patch_thin_macho!(slice)
      data[off, size] = slice
    end
  else
    changed += patch_thin_macho!(data)
  end
  changed
end

# 就地解析 ar 容器，只改写成员内的 Mach-O 字节，不改变成员大小。
def patch_archive_data!(data)
  return 0 unless data[0, 8] == AR_MAGIC

  offset = 8
  changed = 0
  objects = 0

  while offset + 60 <= data.bytesize
    header = data[offset, 60]
    break if header.nil? || header.bytesize < 60

    name = header[0, 16].to_s.strip
    size = header[48, 10].to_s.strip.to_i
    break unless header[58, 2] == "`\n".b

    member_start = offset + 60
    member = data[member_start, size]
    break if member.nil? || member.bytesize < size

    unless name.start_with?('__.SYMDEF') || name == '//' || name == '/'
      objects += 1
    end

    body = member
    if name.start_with?('#1/')
      name_len = name.sub('#1/', '').to_i
      body = member[name_len..] || ''
    end

    n = patch_embedded_binary!(body)
    if n.positive?
      body_offset = member_start + (member.bytesize - body.bytesize)
      data[body_offset, body.bytesize] = body
      changed += n
    end

    offset = member_start + size
    offset += 1 if offset.odd?
  end

  $stats[:archive_objects] += objects
  $stats[:archive_repacked] += 1 if changed.positive?
  changed
end

def patch_embedded_binary!(data)
  if data[0, 8] == AR_MAGIC
    patch_archive_data!(data)
  else
    patch_macho_bytes!(data)
  end
end

def patch_file!(path)
  abs_path = File.expand_path(path)
  data = File.binread(abs_path)
  changed = 0

  if data[0, 4] && data[0, 4].unpack1('N') == FAT_MAGIC
    nfat = data[4, 4].to_s.unpack1('N').to_i
    nfat.times do |i|
      base = 8 + i * 20
      off = data[base + 8, 4].to_s.unpack1('N').to_i
      size = data[base + 12, 4].to_s.unpack1('N').to_i
      next if off <= 0 || size <= 0 || off + size > data.bytesize
      slice = data[off, size]
      n = patch_embedded_binary!(slice)
      if n.positive?
        data[off, size] = slice
        changed += n
      end
    end
  else
    changed += patch_embedded_binary!(data)
  end

  File.binwrite(abs_path, data) if changed.positive?
  changed
end

roots = ['SDK', 'HBuilder-Hello']
archives = roots.flat_map { |r| Dir.glob(File.join(r, '**', '*.a')) }.uniq
machos = roots.flat_map do |r|
  Dir.glob(File.join(r, '**', '*.framework'))
     .reject { |fw| fw.include?('.xcframework/') }
     .map { |fw| File.join(fw, File.basename(fw, '.framework')) }
end.select { |f| File.file?(f) }
machos += roots.flat_map { |r| Dir.glob(File.join(r, '**', '*.dylib')) }

puts "Simulator 构建：开始修补真机专用二进制"
puts "  静态库: #{archives.length} 个，magic 分布: #{archives.map { |p| File.binread(p, 4).unpack1('H*') }.tally.inspect}"
puts "  Framework/dylib: #{machos.length} 个，magic 分布: #{machos.map { |p| File.binread(p, 4).unpack1('H*') }.tally.inspect}"

total = 0
archives.each_with_index do |path, idx|
  n = patch_file!(path)
  total += n
  $stats[:archives] += 1 if n.positive?
  puts "  [#{idx + 1}/#{archives.length}] #{path}: #{n} 处改为 Simulator" if n.positive?
end

machos.each do |path|
  n = patch_file!(path)
  total += n
  $stats[:frameworks] += 1 if n.positive?
  puts "  #{path}: #{n} 处改为 Simulator" if n.positive?
end

puts "Simulator 构建：修补完成，共 #{total} 处 platform/version-min 处理"
puts "  含改动的静态库: #{$stats[:archives]}，framework/dylib: #{$stats[:frameworks]}"
puts "  已就地修补静态库容器: #{$stats[:archive_repacked]}，处理对象文件: #{$stats[:archive_objects]}"
if $stats[:version_min_removed].positive?
  puts "  已删除旧格式 LC_VERSION_MIN_IPHONEOS: #{$stats[:version_min_removed]} 处"
end
