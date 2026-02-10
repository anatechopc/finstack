import 'dart:typed_data';

class RequirementTempContainer {

  RequirementTempContainer(
    this.requirementId,
    this.requirementName,
    this.fileData,
  );
  final String requirementId;
  final String requirementName;
  List<SimpleFileData> fileData;
}

class SimpleFileData {

  SimpleFileData(this.name, this.data);
  final String name;
  final Uint8List data;
}
