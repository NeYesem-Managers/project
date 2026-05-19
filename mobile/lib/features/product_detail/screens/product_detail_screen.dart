import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key});

  // Gereksinim dokümanına uygun Mock Ürün Detay Verisi (FR-PRICE-001 / FR-NUT-001 / FR-HIST-002)
  final Map<String, dynamic> _mockProduct = const {
    'title': 'Fit Tavuk Bowl',
    'restaurant': 'Sağlıklı Mutfak',
    'totalCalorie': 520,
    'protein': '38 g',
    'carbs': '45 g',
    'fat': '12 g',
    'allergens': ['Gluten', 'Yer Fıstığı'], // Ürünün içerdiği alerjenler
    'isFakeDiscount': true, // Sahte indirim şüphesi simülasyonu (FR-HIST-002)
    'lastUpdated': '2 saat önce', // Son güncelleme zamanı (FR-PRICE-001)
    'platforms': [
      {
        'name': 'Yemeksepeti',
        'price': 189.0,
        'oldPrice': 249.0,
        'rating': 4.5,
        'deliveryTime': '25-35 dk',
        'isAvailable': true,
      },
      {
        'name': 'GetirYemek',
        'price': 195.0,
        'oldPrice': 195.0,
        'rating': 4.2,
        'deliveryTime': '20-30 dk',
        'isAvailable': true,
      },
      {
        'name': 'Trendyol Yemek',
        'price': 0.0,
        'oldPrice': 0.0,
        'rating': 0.0,
        'deliveryTime': '-',
        'isAvailable': false, // Platformda mevcut değil durumu (FR-PRICE-003)
      }
    ]
  };

  // Kullanıcının profilinden gelen simüle edilmiş veriler (Alerjen ve Kalori eşleşmesi için)
  final List<String> _userAllergyTags = const ['Yer Fıstığı']; 
  final int _userRemainingCalories = 400; // Kullanıcının o günkü kalan kalori hakkı (Hedef aşımı testi için)

  @override
  Widget build(BuildContext context) {
    // 1. ALERJEN KONTROLÜ (FR-NUT-004)
    final List<String> productAllergens = List<String>.from(_mockProduct['allergens']);
    final bool hasAllergyWarning = productAllergens.any((allergen) => _userAllergyTags.contains(allergen));

    // 2. KALORİ HEDEFİ AŞIM KONTROLÜ (FR-NUT-003)
    final int productCalorie = _mockProduct['totalCalorie'] as int;
    final bool isCalorieExceeded = productCalorie > _userRemainingCalories;

    final bool isFakeDiscount = _mockProduct['isFakeDiscount'] as bool;

    return Scaffold(
      backgroundColor: AppColors.surfaceBackground,
      appBar: AppBar(
        title: Text(_mockProduct['title'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryOrange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KRİTİK UYARI ROZETLERİ (ALERJİ VE KALORİ)
            if (hasAllergyWarning) _buildAllergyAlertCard(),
            if (isCalorieExceeded) _buildCalorieAlertCard(),
            if (isFakeDiscount) _buildFakeDiscountAlertCard(),

            const SizedBox(height: 12),
            // ÜRÜN ANA BİLGİ KARTI
            _buildMainInfoCard(),

            const SizedBox(height: 16),
            // PLATFORMLAR ARASI FİYAT KARŞILAŞTIRMA (US-001)
            const Text('Platform Fiyat Karşılaştırması', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 8),
            
            // UYARI DÜZELTİLDİ: Gereksiz .toList() çağrısı spread operatöründen kaldırıldı.
            ...(_mockProduct['platforms'] as List<Map<String, dynamic>>).map((platform) => _buildPlatformPriceCard(context, platform)),
          ],
        ),
      ),
    );
  }

  // 1. ALERJEN UYARI BİLEŞENİ (FR-NUT-004)
  Widget _buildAllergyAlertCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ALERJEN UYARISI!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Bu ürün profilinizde kayıtlı olan alerjen maddeleri içeriyor: ${_userAllergyTags.join(', ')}', style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // 2. KALORİ AŞIM UYARI BİLEŞENİ (FR-NUT-003)
  Widget _buildCalorieAlertCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade300)),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GÜNLÜK KALORİ HEDEFİ AŞIMI!', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Bu yemek kalan hakkınızı ($_userRemainingCalories kcal) aşıyor. Partnere geçmeden alternatifleri değerlendirmek isteyebilirsiniz.', style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // 3. SAHTE İNDİRİM ŞÜPHESİ BİLEŞENİ (FR-HIST-002 / Görsel Dil Uyumu)
  Widget _buildFakeDiscountAlertCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // UYARI DÜZELTİLDİ: withOpacity yerine .withValues kullanıldı
        color: AppColors.primaryOrange.withValues(alpha: 0.05), 
        borderRadius: BorderRadius.circular(12), 
        // UYARI DÜZELTİLDİ: withOpacity yerine .withValues kullanıldı
        border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.3))
      ),
      child: const Row(
        children: [
          Icon(Icons.trending_up_rounded, color: AppColors.primaryOrange, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SAHTE İNDİRİM ŞÜPHESİ!', style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Bu ürünün indirimli fiyatı, son 30 günlük ortalamanın üzerinde veya çok yakınında tespit edilmiştir.', style: TextStyle(color: Colors.black87, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ÜRÜN DETAY ANA KARTI (FR-NUT-001)
  Widget _buildMainInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_mockProduct['restaurant'].toString(), style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text(_mockProduct['title'].toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('Besin Değerleri (Makro)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 8),
          
          // Makro Besin Tablosu
          Row(
            // HATA DÜZELTİLDİ: MainAxisAlignment.between -> spaceBetween olarak güncellendi.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMacroChip('Kalori', '${_mockProduct['totalCalorie']} kcal', AppColors.primaryOrange),
              _buildMacroChip('Protein', _mockProduct['protein'].toString(), AppColors.healthGreen),
              _buildMacroChip('Karbonh.', _mockProduct['carbs'].toString(), AppColors.partnerBlue),
              _buildMacroChip('Yağ', _mockProduct['fat'].toString(), Colors.purple),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMacroChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // UYARI DÜZELTİLDİ: withOpacity yerine .withValues kullanıldı
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        )
      ],
    );
  }

  // PLATFORM FİYAT LİSTE KARTI VE MAVİ DIŞ YÖNLENDİRME BUTONU (FR-PRICE-001 / FR-LINK-001)
  Widget _buildPlatformPriceCard(BuildContext context, Map<String, dynamic> platform) {
    final bool isAvailable = platform['isAvailable'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sol Kısım: Platform Detayları
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(platform['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    if (isAvailable)
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                          Text(' ${platform['rating']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      )
                  ],
                ),
                const SizedBox(height: 4),
                if (isAvailable) ...[
                  Row(
                    children: [
                      Text('${(platform['price'] as double).toStringAsFixed(0)} TL ', style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                      if (platform['price'] < platform['oldPrice'])
                        Text('${(platform['oldPrice'] as double).toStringAsFixed(0)} TL', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Teslimat: ${platform['deliveryTime']} | Güncelleme: ${_mockProduct['lastUpdated']}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ] else
                  const Text('Bu platformda mevcut değil', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          
          // Sağ Kısım: Mavi Renkli Dış Uygulamaya Geçiş Butonu (FR-LINK-001)
          if (isAvailable)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.partnerBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${platform['name']} uygulamasına güvenli geçiş başlatılıyor (Deep Link)...'),
                    backgroundColor: AppColors.partnerBlue,
                  ),
                );
              },
              child: const Text('Aç', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
        ],
      ),
    );
  }
}