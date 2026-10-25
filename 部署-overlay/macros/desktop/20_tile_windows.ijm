// desktop/ 目录占位：依赖桌面窗口行为的宏（按 R3 不进 common）
// 例：selectWindow 依赖具体窗口标题，web 端不承诺
macro "工具-排列全部窗口" {
  if (nImages==0) newImage("SampleArrange", "8-bit ramp", 200, 200, 1);
  run("Tile");
  selectWindow("SampleArrange");
}
