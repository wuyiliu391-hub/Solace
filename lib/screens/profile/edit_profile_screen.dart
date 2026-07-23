import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/user.dart';
import '../../repositories/local_storage_repository.dart';

class EditProfileScreen extends StatefulWidget {
  final User user;

  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nicknameController;
  late TextEditingController _signatureController;
  late TextEditingController _bioController;
  late TextEditingController _statusController;
  String? _gender;
  String? _birthday;

  final List<String> _genderOptions = ['男', '女', '保密'];
  final List<String> _presetStatuses = ['开心', '忙碌', 'emo中', '学习中', '休息中', '请勿打扰'];

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.user.nickname);
    _signatureController = TextEditingController(text: widget.user.signature ?? '');
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _statusController = TextEditingController(text: widget.user.status ?? '');
    _gender = widget.user.gender;
    _birthday = widget.user.birthday;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _signatureController.dispose();
    _bioController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('编辑资料'),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text('保存', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('基本信息', colorScheme),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTextField(
                      label: '昵称',
                      controller: _nicknameController,
                      maxLength: 20,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: '个性签名',
                      controller: _signatureController,
                      maxLength: 50,
                      hint: '写一句个性签名吧',
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('个人状态', colorScheme),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '快捷选择',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presetStatuses.map((status) {
                        final isSelected = _statusController.text == status;
                        return ChoiceChip(
                          label: Text(status),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _statusController.text = selected ? status : '';
                              _statusController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _statusController.text.length),
                              );
                            });
                          },
                          selectedColor: colorScheme.primary,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : colorScheme.onSurface,
                            fontSize: 13,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      label: '自定义状态',
                      controller: _statusController,
                      maxLength: 20,
                      hint: '输入你的当前状态',
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('个人资料', colorScheme),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildGenderSelector(colorScheme),
                    const SizedBox(height: 16),
                    _buildBirthdayPicker(colorScheme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('个人简介', colorScheme),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildTextField(
                  label: '个人简介',
                  controller: _bioController,
                  maxLines: 4,
                  maxLength: 200,
                  hint: '介绍一下自己吧',
                  colorScheme: colorScheme,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: colorScheme.primary,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required ColorScheme colorScheme,
    int maxLines = 1,
    int? maxLength,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
        hintText: hint,
        hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  Widget _buildGenderSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '性别',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _genderOptions.map((gender) {
            final isSelected = _gender == gender;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ChoiceChip(
                label: Text(gender),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _gender = selected ? gender : null;
                  });
                },
                selectedColor: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : colorScheme.onSurface,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBirthdayPicker(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生日',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectBirthday,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _birthday ?? '选择生日',
                  style: TextStyle(
                    color: _birthday != null ? colorScheme.onSurface : colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 16,
                  ),
                ),
                Icon(Icons.calendar_today, size: 20, color: colorScheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthday = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称不能为空')),
      );
      return;
    }

    final updatedUser = widget.user.copyWith(
      nickname: nickname,
      signature: _signatureController.text.trim(),
      bio: _bioController.text.trim(),
      status: _statusController.text.trim(),
      gender: _gender,
      birthday: _birthday,
    );

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.saveUser(updatedUser);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料已保存')),
      );
      Navigator.pop(context, true);
    }
  }
}
