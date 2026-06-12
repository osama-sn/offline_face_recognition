class FaceTemplate {
  const FaceTemplate({
    required this.id,
    required this.embedding,
    required this.createdAt,
    this.label,
    this.metadata = const {},
    this.updatedAt,
  });

  final String id;
  final String? label;
  final List<double> embedding;
  final Map<String, Object?> metadata;
  final DateTime createdAt;
  final DateTime? updatedAt;

  FaceTemplate copyWith({
    String? id,
    String? label,
    List<double>? embedding,
    Map<String, Object?>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FaceTemplate(
      id: id ?? this.id,
      label: label ?? this.label,
      embedding: embedding ?? this.embedding,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
