#!/bin/zsh

echo "=== 清除 SMB 缓存并重新测试 ==="

# 卸载所有 SMB
echo "卸载挂载..."
umount /Volumes/3211 2>/dev/null
umount /Volumes/HDD-Storage123 2>/dev/null
sleep 2

# 重新挂载
echo "重新挂载..."
mount_smbfs //casaos:casaos@10.0.0.72/3211 /Volumes/3211 2>/dev/null
mount_smbfs //casaos:casaos@10.0.0.72/HDD-Storage123 /Volumes/HDD-Storage123 2>/dev/null
sleep 2

# 多次计算 MD5
echo ""
echo "=== 测试 /Volumes/3211/ ==="
for i in {1..3}; do
    md5=$(md5sum /Volumes/3211/indextts_example_wavs.zip | cut -d' ' -f1)
    echo "第 $i 次: $md5"
done

echo ""
echo "=== 测试 /Volumes/HDD-Storage123/3211/ ==="
for i in {1..3}; do
    md5=$(md5sum /Volumes/HDD-Storage123/3211/indextts_example_wavs.zip | cut -d' ' -f1)
    echo "第 $i 次: $md5"
done

echo ""
echo "=== 检查文件详细信息 ==="
stat -f "大小: %z, 修改时间: %Sm" /Volumes/3211/indextts_example_wavs.zip
stat -f "大小: %z, 修改时间: %Sm" /Volumes/HDD-Storage123/3211/indextts_example_wavs.zip
