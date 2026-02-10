final class MenuModel {

  const MenuModel({
    required this.title,
    required this.redirectPath,
    this.logoPath,
    this.show = true,
  });
  final String title;
  final String? logoPath;
  final String redirectPath;
  final bool show;
}
