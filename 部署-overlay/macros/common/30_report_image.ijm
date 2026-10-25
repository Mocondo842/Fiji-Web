// 30_report_image.ijm — 图像信息报告（V13 功能测试用）
// 把当前图像的关键参数写进窗口标题（重命名），使自动化可通过 DOM 验证结果
if (nImages==0) {
  print("[30_report_image] 无图像");
} else {
  info = getWidth() + "x" + getHeight() + "-bit" + bitDepth + "-ch" + nChannels + "-z" + nSlices + "-t" + nFrames;
  rename("REPORTED_" + info);
  print("[30_report_image] " + info);
}
