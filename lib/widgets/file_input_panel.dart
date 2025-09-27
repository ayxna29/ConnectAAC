import 'package:flutter/cupertino.dart';

class FileInputPanel extends StatefulWidget {
  final List<String> filenames;
  final Future<void> Function(String name) onAdd;
  final Future<void> Function(String name) onRemove;
  final bool loading;

  const FileInputPanel({
    super.key,
    required this.filenames,
    required this.onAdd,
    required this.onRemove,
    this.loading = false,
  });

  @override
  State<FileInputPanel> createState() => _FileInputPanelState();
}

class _FileInputPanelState extends State<FileInputPanel> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd(name);
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text('Failed to add file: $e'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add Flashcard File',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add a symbol filename (e.g. road.svg). This creates a flashcard row and adds it to the list.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                placeholder: 'Enter filename (e.g. road.svg)',
                onSubmitted: (_) => _handleAdd(),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton.filled(
              onPressed: widget.loading || _busy ? null : _handleAdd,
              child: widget.loading || _busy
                  ? const CupertinoActivityIndicator()
                  : const Text('Add File'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: widget.filenames.map((fn) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey5,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fn),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => widget.onRemove(fn),
                    child: const Icon(
                      CupertinoIcons.trash,
                      size: 18,
                      color: CupertinoColors.systemRed,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
