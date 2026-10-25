// 00_common_tools.ijm — 命名块宏集：供 ?install-macro= 一次性装入 Plugins>Macros
// 注意：装入菜单必须用 macro "命名" 块格式（阶段0实测结论：顶层命令式宏装入后无可见落位）
macro "工具-栈转系列图" {
  if (nImages==0) newImage("SampleStack", "8-bit ramp", 256, 256, 1, 3, 1);
  run("Stack to Images");
}
macro "工具-增强对比度" {
  if (nImages==0) newImage("SampleContrast", "8-bit ramp", 256, 256, 1);
  run("Enhance Contrast", "saturated=0.35");
}
macro "工具-图像反相" {
  if (nImages==0) newImage("SampleInvert", "8-bit ramp", 256, 256, 1);
  run("Invert");
}
macro "工具-版本报告" {
  print("ImageJ 版本: " + getVersion());
}
