import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  // Dokümandaki sıralama kriterleri (FR-SRCH-003)
  String _selectedSort = 'Fiyat (Artan)';
  final List<String> _sortOptions = ['Fiyat (Artan)', 'Fiyat (Azalan)', 'Restoran Puanı', 'Mesafe'];

  // Dokümandaki filtreleme durumları (FR-SRCH-002)
  bool _onlyRealDiscount = false;
  RangeValues _priceRange = const RangeValues(50, 500);
  
  // UYARI DÜZELTİLDİ: Değeri sonradan değişmediği için 'final' yapıldı.
  final RangeValues _calorieRange = const RangeValues(100, 1200);
  
  String _selectedCuisine = 'Hepsi';
  final List<String> _cuisines = ['Hepsi', 'Çiğ Köfte', 'Burger', 'Ev Yemekleri', 'Tatlı', 'Uzak Doğu'];

  // Arama sonuçları için entegre edilmiş bir Mock Veri Seti (FR-SRCH-004)
  final List<Map<String, dynamic>> _allProducts = [
    {
      'title': 'Duble Çiğ Köfte Dürüm',
      'restaurant': 'Has Çiğ Köfte Dünyası',
      'cuisine': 'Çiğ Köfte',
      'price': 200.0,
      'calorie': 450,
      'rating': 4.5,
      'distance': 1.2,
      'hasRealDiscount': false,
    },
    {
      'title': 'Jets Burger Menü',
      'restaurant': 'Jets Burger',
      'cuisine': 'Burger',
      'price': 240.0,
      'calorie': 890,
      'rating': 4.8,
      'distance': 2.5,
      'hasRealDiscount': true,
    },
    {
      'title': 'Berry Hibiscus',
      'restaurant': 'Big Bubble Tea',
      'cuisine': 'Tatlı',
      'price': 203.9,
      'calorie': 250,
      'rating': 4.2,
      'distance': 0.8,
      'hasRealDiscount': true,
    }
  ];

  List<Map<String, dynamic>> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _filteredProducts = List.from(_allProducts);
  }

  // Akıllı Arama ve Filtreleme Algoritması (FR-SRCH-002)
  void _applyFiltersAndSearch(String query) {
    setState(() {
      _filteredProducts = _allProducts.where((product) {
        final matchesQuery = product['title'].toString().toLowerCase().contains(query.toLowerCase()) ||
            product['restaurant'].toString().toLowerCase().contains(query.toLowerCase());
        
        final matchesCuisine = _selectedCuisine == 'Hepsi' || product['cuisine'] == _selectedCuisine;
        
        final price = product['price'] as double;
        final matchesPrice = price >= _priceRange.start && price <= _priceRange.end;
        
        final calorie = product['calorie'] as int;
        final matchesCalorie = calorie >= _calorieRange.start && calorie <= _calorieRange.end;
        
        final matchesDiscount = !_onlyRealDiscount || (product['hasRealDiscount'] as bool);

        return matchesQuery && matchesCuisine && matchesPrice && matchesCalorie && matchesDiscount;
      }).toList();

      // Sıralama Algoritması (FR-SRCH-003)
      if (_selectedSort == 'Fiyat (Artan)') {
        _filteredProducts.sort((a, b) => (a['price'] as double).compareTo(b['price'] as double));
      } else if (_selectedSort == 'Fiyat (Azalan)') {
        _filteredProducts.sort((a, b) => (b['price'] as double).compareTo(a['price'] as double));
      } else if (_selectedSort == 'Restoran Puanı') {
        _filteredProducts.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      } else if (_selectedSort == 'Mesafe') {
        _filteredProducts.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBackground,
      appBar: AppBar(
        title: const Text('Keşif ve Arama', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryOrange,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ARAMA VE SIRALAMA ÜST PANELİ
          Container(
            color: AppColors.surfaceLight,
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: _applyFiltersAndSearch,
                  decoration: InputDecoration(
                    hintText: 'Yemek veya restoran adı arayın...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.primaryOrange),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              _applyFiltersAndSearch('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primaryOrange),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                
                Row(
                  // HATA DÜZELTİLDİ: MainAxisAlignment.between -> spaceBetween yapıldı
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sıralama kriteri:', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
                    DropdownButton<String>(
                      value: _selectedSort,
                      icon: const Icon(Icons.swap_vert_rounded, color: AppColors.primaryOrange),
                      underline: Container(height: 1, color: Colors.transparent),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          _selectedSort = newValue;
                          _applyFiltersAndSearch(_searchController.text);
                        }
                      },
                      items: _sortOptions.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          _buildFilterBarButton(context),

          // SONUÇ LİSTESİ
          Expanded(
            child: _filteredProducts.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final item = _filteredProducts[index];
                      return _buildSearchResultCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBarButton(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Filtreler (Mutfak: $_selectedCuisine)',
            // HATA DÜZELTİLDİ: Tanımlı olmayan Colors.black60 yerine const yapıya uygun Colors.black54 kullanıldı
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black54),
          ),
          TextButton.icon(
            onPressed: () => _showFilterBottomSheet(context),
            icon: const Icon(Icons.tune_rounded, size: 16, color: AppColors.primaryOrange),
            label: const Text('Filtreleri Düzenle', style: TextStyle(color: AppColors.primaryOrange, fontSize: 13)),
          )
        ],
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gelişmiş Filtreleme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(height: 20),
                  
                  SwitchListTile(
                    title: const Text('Sadece Gerçek İndirimli Ürünler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    value: _onlyRealDiscount,
                    // UYARI DÜZELTİLDİ: Malzeme tasarım standartlarına göre güncellendi
                    thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.selected)) return AppColors.healthGreen;
                      return null;
                    }),
                    trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.selected)) return AppColors.healthGreen.withValues(alpha: 0.5);
                      return null;
                    }),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool value) {
                      setModalState(() => _onlyRealDiscount = value);
                      _applyFiltersAndSearch(_searchController.text);
                    },
                  ),
                  
                  const Text('Mutfak Türü', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: _selectedCuisine,
                    isExpanded: true,
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setModalState(() => _selectedCuisine = newValue);
                        _applyFiltersAndSearch(_searchController.text);
                      }
                    },
                    items: _cuisines.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  Text('Fiyat Aralığı: ${_priceRange.start.toStringAsFixed(0)} TL - ${_priceRange.end.toStringAsFixed(0)} TL', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  RangeSlider(
                    values: _priceRange,
                    min: 50,
                    max: 500,
                    activeColor: AppColors.primaryOrange,
                    onChanged: (RangeValues values) {
                      setModalState(() => _priceRange = values);
                      _applyFiltersAndSearch(_searchController.text);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> item) {
    return Card(
      color: AppColors.surfaceLight,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        title: Row(
          // HATA DÜZELTİLDİ: MainAxisAlignment.between -> spaceBetween yapıldı
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(item['title'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Text('${(item['price'] as double).toStringAsFixed(0)} TL', style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item['restaurant'].toString(), style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 2),
                Text(item['rating'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 2),
                Text('${item['distance']} km', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 12),
                if (item['hasRealDiscount'] as bool)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      // UYARI DÜZELTİLDİ: withOpacity yerine .withValues() kullanıldı
                      color: AppColors.healthGreen.withValues(alpha: 0.1), 
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Gerçek İndirim', style: TextStyle(color: AppColors.healthGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
              ],
            )
          ],
        ),
        onTap: () {},
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('Aramanızla Eşleşen Sonuç Bulunamadı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 4),
          const Text('Lütfen filtreleri gevşetmeyi veya farklı kelimeler aramayı deneyin.', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}