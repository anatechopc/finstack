/// For testing purposes only.
/// copy-paste back the code to user_bloc if testing
/// again.

// Future<List<User>> _addTestUsers() async {
//   final users = <User>[];
//
//   for (var i = 0; i < 10; i++) {
//     await Future.delayed(Duration(seconds: 1));
//     users.add(User.create(
//       firstName: 'firstName $i',
//       lastName: 'lastName $i',
//       mobileNumber: 'mobileNumber $i',
//       emailAddress: 'emailAddress $i',
//       profilePhotoUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'profilePhotoUrl $i',
//       ),
//       photoWithValidIdUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'photoWithValidIdurl $i',
//       ),
//       userRole: UserRole.customer,
//       birthDate: DateTime.now(),
//       facebookProfileUrl: 'facebookProfileUrl $i',
//       addressId: 'addressId $i',
//     ));
//   }
//
//   return users;
// }
//
// void _test() async {
//   try {
//     // final users = await _addTestUsers().then((users) {
//     //   return users.map((user) {
//     //     return _userRepository.add(data: user);
//     //   });
//     // });
//     // await Future.wait(users);
//     // debugPrint('finish adding users');
//
//     await Future.delayed(Duration(seconds: 3));
//     debugPrint('start load');
//     _userRepository.loadNext();
//     await Future.delayed(Duration(seconds: 3));
//     debugPrint('load 2');
//     _userRepository.loadNext();
//     await Future.delayed(Duration(seconds: 3));
//     debugPrint('adding more');
//
//     // add here
//     _userRepository.add(data: User.create(
//       firstName: 'firstName 21',
//       lastName: 'lastName 21',
//       mobileNumber: 'mobileNumber 21',
//       emailAddress: 'emailAddress 21',
//       profilePhotoUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'profilePhotoUrl 21',
//       ),
//       photoWithValidIdUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'photoWithValidIdurl 21',
//       ),
//       userRole: UserRole.customer,
//       birthDate: DateTime.now(),
//       facebookProfileUrl: 'facebookProfileUrl 21',
//       addressId: 'addressId 21',
//     ));
//     debugPrint('add 21');
//     await Future.delayed(Duration(seconds: 5));
//     _userRepository.add(data: User.create(
//       firstName: 'firstName 22',
//       lastName: 'lastName 22',
//       mobileNumber: 'mobileNumber 22',
//       emailAddress: 'emailAddress 22',
//       profilePhotoUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'profilePhotoUrl 22',
//       ),
//       photoWithValidIdUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'photoWithValidIdurl 22',
//       ),
//       userRole: UserRole.customer,
//       birthDate: DateTime.now(),
//       facebookProfileUrl: 'facebookProfileUrl 22',
//       addressId: 'addressId 21',
//     ));
//
//     debugPrint('add 22');
//   } catch (err) {
//     print(err);
//   }
//
//   void addAnotherTest() async {
//     final ddd = Random().nextInt(1000);
//     await _userRepository.add(data: User.create(
//       firstName: 'firstName $ddd',
//       lastName: 'lastName $ddd',
//       mobileNumber: 'mobileNumber $ddd',
//       emailAddress: 'emailAddress $ddd',
//       profilePhotoUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'profilePhotoUrl $ddd',
//       ),
//       photoWithValidIdUrl: ImageUrl(
//         name: 'profile',
//         isPrimary: true,
//         original: 'photoWithValidIdurl $ddd',
//       ),
//       userRole: UserRole.customer,
//       birthDate: DateTime.now(),
//       facebookProfileUrl: 'facebookProfileUrl $ddd',
//       addressId: 'addressId $ddd',
//     ));
//     debugPrint('added $ddd');
//   }
// }