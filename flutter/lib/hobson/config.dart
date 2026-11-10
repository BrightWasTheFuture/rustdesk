import 'package:flutter/material.dart';

/// JCB Remote is this fork's only UI. A function (not a const) so call
/// sites can keep the upstream widgets compiled beside it.
bool hobsonUiEnabled() => true;

const String kHobsonDisplayName = 'JCB Remote';
const String kHobsonAppName = 'JCBRemote';
const Color kJcbBlue = Color(0xFF1976D2);
const String kHobsonRelayOption = 'hobson-relay';
const String kHobsonPrivacyOption = 'hobson-privacy';
const String kHobsonLogFileName = 'hobson-connections.json';
