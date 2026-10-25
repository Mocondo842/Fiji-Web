// web/ 目录占位：仅 web 端使用的宏收尾逻辑（如对话框式保存 saveAs("Tiff") 走浏览器下载）
// R5：web 宏模板必须用无路径 saveAs 触发保存对话框→浏览器下载；写死路径只会落入浏览器内部文件系统
macro "工具-保存当前图(TIFF)" {
  if (nImages==0) newImage("SampleSave", "8-bit ramp", 256, 256, 1);
  saveAs("Tiff");  // 无路径 → 弹保存对话框 → 浏览器下载
}
