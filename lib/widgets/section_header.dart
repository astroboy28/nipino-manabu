import 'package:flutter/material.dart'; 
class SectionHeader extends StatelessWidget { 
  const SectionHeader({super.key, required this.tag}); 
  final String tag; 
  @override 
  Widget build(BuildContext context) => Text(tag); 
} 
