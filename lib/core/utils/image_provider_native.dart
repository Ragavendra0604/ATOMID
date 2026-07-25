import 'dart:io';
import 'package:flutter/material.dart';

ImageProvider getFileImageProvider(String path) {
  return FileImage(File(path));
}
