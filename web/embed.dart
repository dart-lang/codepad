// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_pad/embed/embed.dart' as embed;
import 'package:dart_pad/polymer/polymer.dart';

void main() {
  Polymer.whenReady().then((_) {
    embed.init();
  });
}
