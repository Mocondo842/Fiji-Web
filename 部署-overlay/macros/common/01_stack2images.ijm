// 01_stack2images.ijm — 栈转系列图（common：无窗口依赖，双端可跑）
// 一键运行时无图则自动生成 256x256x3 渐变栈样例，保证可独立执行
if (nImages==0) {
  newImage("SampleStack", "8-bit ramp", 256, 256, 1, 3, 1);
}
run("Stack to Images");
print("[01_stack2images] 完成：栈已转系列图，窗口数=" + nImages);
