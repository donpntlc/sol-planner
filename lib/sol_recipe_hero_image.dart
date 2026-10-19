// Rezept-Header: Standard-Bild, sonst gecachtes KI-Bild, sonst Button zum Erzeugen (Imagen).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sol/ai_recipe_image.dart' as ari;

typedef STr = String Function(String key);

class SolRecipeHeroImage extends StatefulWidget {
  const SolRecipeHeroImage({
    super.key,
    required this.foodName,
    this.imageAssetPath,
    this.portionHint,
    this.firstInstructionLine,
    this.apiKey,
    required this.t,
    this.height = 200,
  });

  final String foodName;
  final String? imageAssetPath;
  final String? portionHint;
  final String? firstInstructionLine;
  final String? apiKey;
  final STr t;
  final double height;

  @override
  State<SolRecipeHeroImage> createState() => _SolRecipeHeroImageState();
}

class _SolRecipeHeroImageState extends State<SolRecipeHeroImage> {
  Uint8List? _aiBytes;
  bool _assetFailed = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_readCache());
  }

  Future<void> _readCache() async {
    final b = await ari.readCachedRecipeImage(widget.foodName);
    if (!mounted) return;
    if (b != null) {
      setState(() => _aiBytes = b);
    }
  }

  Future<void> _generate() async {
    final k = widget.apiKey?.trim() ?? '';
    if (k.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prompt = ari.buildImagenFoodPrompt(
        dishName: widget.foodName,
        portionHint: widget.portionHint,
        firstInstruction: widget.firstInstructionLine,
      );
      final png = await ari.requestImagenRecipeImagePng(
        apiKey: k,
        prompt: prompt,
      );
      await ari.writeCachedRecipeImage(widget.foodName, png);
      if (!mounted) return;
      setState(() {
        _aiBytes = png;
        _loading = false;
        _error = null;
        _assetFailed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_aiBytes != null) {
      return _framed(
        context,
        Image.memory(
          _aiBytes!,
          width: double.infinity,
          height: widget.height,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    if (widget.imageAssetPath != null &&
        widget.imageAssetPath!.isNotEmpty &&
        !_assetFailed) {
      return _framed(
        context,
        Image.asset(
          widget.imageAssetPath!,
          width: double.infinity,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _assetFailed = true);
            });
            return const SizedBox.shrink();
          },
        ),
      );
    }

    return _framed(
      context,
      SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 40,
              color: Colors.white.withValues(alpha: 0.32),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                widget.t('recipe_ai_placeholder_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.45),
                  height: 1.28,
                ),
              ),
            ),
            if (widget.apiKey != null && widget.apiKey!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                FilledButton.tonal(
                  onPressed: _loading ? null : _generate,
                  child: Text(widget.t('recipe_ai_generate')),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.t('recipe_ai_key_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.t('recipe_ai_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFFE57373),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      useFixedHeight: true,
    );
  }

  Widget _framed(
    BuildContext context,
    Widget inner, {
    bool useFixedHeight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          height: useFixedHeight ? widget.height : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.85),
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.5),
            child: useFixedHeight
                ? Center(child: inner)
                : inner,
          ),
        ),
      ),
    );
  }
}
