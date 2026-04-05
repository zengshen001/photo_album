class OcrFeatureFlags {
  const OcrFeatureFlags._();

  // 默认关闭 OCR 预埋能力，确保当前运行逻辑保持不变。
  // 后续需要验证 OCR 时，只打开这个开关并接入实际依赖即可。
  static const bool enablePhotoOcr = false;
}
