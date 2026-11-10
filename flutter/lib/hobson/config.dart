/// Hobson Remote is this fork's only UI. A function (not a const) so call
/// sites can keep the upstream widgets compiled beside it.
bool hobsonUiEnabled() => true;

const String kHobsonDisplayName = 'Hobson Remote';
const String kHobsonAppName = 'HobsonRemote';
const String kHobsonRelayOption = 'hobson-relay';
const String kHobsonPrivacyOption = 'hobson-privacy';
const String kHobsonLogFileName = 'hobson-connections.json';
