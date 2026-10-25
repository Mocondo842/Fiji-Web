// 04_split_channels.ijm — 通道拆分（common；样例自举为 RGB）
if (nImages==0) {
  newImage("SampleRGB", "RGB black", 256, 256, 1, 3, 1);
  run("Fire");
}
if (bitDepth==24) {
  run("Split Channels");
  print("[04_split_channels] 完成：RGB 已拆分，窗口数=" + nImages);
} else {
  print("[04_split_channels] 当前图非 RGB(bit=" + bitDepth + ")，跳过拆分");
}
