import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../core/logger.dart';
import '../../core/theme.dart';

class AddContactBottomSheet extends StatefulWidget {
  final Function(String name, String phone) onSave;
  final VoidCallback? onPickContact;

  const AddContactBottomSheet({
    super.key,
    required this.onSave,
    this.onPickContact,
  });

  /// Chuẩn hóa số điện thoại (loại bỏ khoảng trắng, dấu gạch nối, chuẩn hóa đầu số +84 thành 0)
  static String normalizePhoneNumber(String rawPhone) {
    if (rawPhone.trim().isEmpty) return '';
    // Loại bỏ các ký tự phân cách như dấu cách, gạch ngang, ngoặc đơn, dấu chấm
    String cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    
    // Nếu bắt đầu bằng +84, đổi thành 0
    if (cleaned.startsWith('+84')) {
      cleaned = '0${cleaned.substring(3)}';
    } else if (cleaned.startsWith('84') && cleaned.length >= 10 && !cleaned.startsWith('840')) {
      cleaned = '0${cleaned.substring(2)}';
    }
    
    // Giữ lại định dạng số hoặc dấu + quốc tế nếu có
    if (!cleaned.startsWith('+')) {
      cleaned = cleaned.replaceAll(RegExp(r'\D'), '');
    }
    return cleaned;
  }

  @override
  State<AddContactBottomSheet> createState() => _AddContactBottomSheetState();
}

class _AddContactBottomSheetState extends State<AddContactBottomSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();

  final List<String> _quickSuggestions = [
    'Con gái',
    'Con trai',
    'Vợ / Chồng',
    'Cháu ruột',
    'Trạm Y tế xã',
    'Bác sĩ gia đình',
    'Tổ dân phố',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _selectSuggestion(String name) {
    setState(() {
      _nameController.text = name;
    });
    _phoneFocusNode.requestFocus();
  }

  Future<void> _pickFromPhoneContacts() async {
    try {
      AppLogger.i('📱 Mở danh bạ điện thoại để chọn người thân...', tag: 'CONTACTS');
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Bác ơi, vui lòng cấp quyền danh bạ để cháu hỗ trợ Bác chọn số người thân nhé ạ.',
                style: TextStyle(fontFamily: 'Roboto', fontSize: 16),
              ),
              backgroundColor: AppColors.sosOrange,
              action: SnackBarAction(
                label: 'Cài đặt',
                textColor: Colors.white,
                onPressed: () => FlutterContacts.permissions.openSettings(),
              ),
            ),
          );
        }
        return;
      }

      // Mở trình chọn danh bạ Native với đầy đủ thuộc tính (Name, Phone,...)
      Contact? contact = await FlutterContacts.native.showPicker(
        properties: ContactProperties.all,
      );

      if (contact == null) {
        AppLogger.i('Bác đã đóng hoặc hủy chọn từ danh bạ', tag: 'CONTACTS');
        return;
      }

      // 1. Lấy Tên hiển thị
      final displayName = (contact.displayName ?? '').trim();
      final firstName = (contact.name?.first ?? '').trim();
      final lastName = (contact.name?.last ?? '').trim();
      String name = displayName.isNotEmpty
          ? displayName
          : '$firstName $lastName'.trim();

      // 2. Lấy danh sách số điện thoại (Kèm Fallback query theo contact.id nếu mảng phones rỗng)
      List<Phone> phones = contact.phones;
      final contactId = contact.id;
      if (phones.isEmpty && contactId != null && contactId.isNotEmpty) {
        AppLogger.d('Mảng phones từ showPicker trống, thực hiện fallback get(id: $contactId)', tag: 'CONTACTS');
        final fullContact = await FlutterContacts.get(
          contactId,
          properties: ContactProperties.all,
        );
        if (fullContact != null && fullContact.phones.isNotEmpty) {
          phones = fullContact.phones;
          if (name.isEmpty && (fullContact.displayName ?? '').trim().isNotEmpty) {
            name = (fullContact.displayName ?? '').trim();
          }
        }
      }

      // 3. Chọn số điện thoại chính / số đầu tiên và chuẩn hóa
      String rawPhone = '';
      if (phones.isNotEmpty) {
        final primaryPhone = phones.firstWhere(
          (p) => p.isPrimary == true,
          orElse: () => phones.first,
        );
        rawPhone = primaryPhone.number;
      }

      final cleanPhone = AddContactBottomSheet.normalizePhoneNumber(rawPhone);
      AppLogger.i('✅ Đã chọn thành công từ danh bạ: "$name" ($cleanPhone)', tag: 'CONTACTS');

      if (mounted) {
        setState(() {
          if (name.isNotEmpty) _nameController.text = name;
          if (cleanPhone.isNotEmpty) _phoneController.text = cleanPhone;
        });

        // Phản hồi xúc giác & thông báo cho Bác
        if (cleanPhone.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Đã chọn: $name ($cleanPhone)',
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.primaryGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          // Trường hợp liên hệ chưa lưu số điện thoại nào trong danh bạ
          _phoneFocusNode.requestFocus();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bác ơi, liên hệ "$name" chưa có số điện thoại trong danh bạ. Bác vui lòng nhập số điện thoại giúp cháu nhé ạ.',
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 15),
              ),
              backgroundColor: AppColors.sosOrange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, st) {
      AppLogger.e('Lỗi khi chọn liên hệ từ danh bạ: $e', tag: 'CONTACTS', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở danh bạ thiết bị. Bác vui lòng nhập trực tiếp giúp cháu nhé ạ.'),
            backgroundColor: AppColors.sosOrange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.mediumGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Thêm liên hệ người thân',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn nhanh người thân, chọn từ danh bạ hoặc nhập trực tiếp:',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Nút Chọn từ danh bạ điện thoại
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _pickFromPhoneContacts,
                icon: const Icon(Icons.contacts_rounded, color: AppColors.primaryGreen, size: 24),
                label: const Text(
                  'CHỌN TỪ DANH BẠ ĐIỆN THOẠI',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryGreen, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  backgroundColor: const Color(0xFFE8F5E9),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Gợi ý chọn nhanh 1 chạm (Quick chips)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickSuggestions.map((suggestion) {
                final isSelected = _nameController.text == suggestion;
                return ActionChip(
                  label: Text(
                    suggestion,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.primaryGreenDark,
                    ),
                  ),
                  backgroundColor: isSelected ? AppColors.primaryGreen : const Color(0xFFE8F5E9),
                  side: BorderSide(
                    color: isSelected ? AppColors.primaryGreen : const Color(0xFFA5D6A7),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onPressed: () => _selectSuggestion(suggestion),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            
            // Name Input
            SizedBox(
              height: 56,
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'Tên người thân',
                  hintText: 'VD: Con gái Lan, Bác Năm...',
                  prefixIcon: const Icon(Icons.person_outline, color: AppColors.primaryGreen),
                  hintStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    color: Color(0xFF999999),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Phone Input
            SizedBox(
              height: 56,
              child: TextField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                decoration: InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: 'VD: 0912 345 678',
                  prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primaryGreen),
                  hintStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    color: Color(0xFF999999),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  if (_nameController.text.trim().isNotEmpty && _phoneController.text.trim().isNotEmpty) {
                    widget.onSave(_nameController.text.trim(), _phoneController.text.trim());
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 1,
                ),
                child: const Text(
                  'LƯU LIÊN HỆ NGƯỜI THÂN',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
