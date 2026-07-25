import 'package:flutter/material.dart';

ImageProvider getFileImageProvider(String path) {
  return NetworkImage(path);
}
