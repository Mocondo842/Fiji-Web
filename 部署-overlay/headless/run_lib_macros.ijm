// headless 批处理验证：串行运行宏库 common 三宏（证明「至少一条路径成功」+ 宏库单一来源被桌面复用）
LOG = "C:/Users/sr123/ijweb/headless/batch_result.log";
File.append("HEADLESS_BEGIN ver=" + getVersion(), LOG);
print("HEADLESS_BEGIN ver=" + getVersion());
runMacro("C:/Users/sr123/ijweb/macros/common/01_stack2images.ijm");
File.append("AFTER_01 nImages=" + nImages, LOG);
print("AFTER_01 nImages=" + nImages);
close("*");
runMacro("C:/Users/sr123/ijweb/macros/common/02_enhance_contrast.ijm");
File.append("AFTER_02 nImages=" + nImages, LOG);
print("AFTER_02 nImages=" + nImages);
close("*");
runMacro("C:/Users/sr123/ijweb/macros/common/03_invert_image.ijm");
File.append("AFTER_03 nImages=" + nImages, LOG);
print("AFTER_03 nImages=" + nImages);
File.append("HEADLESS_END", LOG);
print("HEADLESS_END");
