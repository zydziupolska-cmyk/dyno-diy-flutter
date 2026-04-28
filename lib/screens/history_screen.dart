import 'package:flutter/material.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Symulacja bazy danych (w przyszłości to będzie pobierane z Hive/Isar)
  final List<Map<String, dynamic>> savedRuns = [
    {
      "name": "Stage 2 (Wydech + IC)",
      "date": "28 Kwi 2026",
      "hp": 385,
      "nm": 490,
      "color": Colors.redAccent
    },
    {
      "name": "Stage 1 (Chiptuning)",
      "date": "15 Kwi 2026",
      "hp": 350,
      "nm": 450,
      "color": Colors.orangeAccent
    },
    {
      "name": "Seria (Fabryka)",
      "date": "10 Kwi 2026",
      "hp": 320,
      "nm": 407,
      "color": Colors.grey
    },
  ];

  // Lista przechowująca indeksy zaznaczonych przejazdów (do porównania)
  List<int> selectedRuns = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archiwum Pomiarów'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Eksportuj do PDF/PNG',
            onPressed: () {
              // Tu dodamy eksport PNG
              debugPrint("Eksport PNG/PDF");
            },
          ),
          IconButton(
            icon: const Icon(Icons.data_object),
            tooltip: 'Eksportuj surowe dane (XML/CSV)',
            onPressed: () {
              // Tu dodamy eksport XML
              debugPrint("Eksport XML");
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Zaznacz przejazdy, które chcesz nałożyć na jeden wykres (Before & After).',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: savedRuns.length,
              itemBuilder: (context, index) {
                final run = savedRuns[index];
                final isSelected = selectedRuns.contains(index);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isSelected ? Colors.grey[850] : Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: isSelected ? Colors.blueAccent : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: run["color"].withOpacity(0.2),
                      child: Icon(Icons.show_chart, color: run["color"]),
                    ),
                    title: Text(run["name"], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Data: ${run["date"]}\nMoc: ${run["hp"]} KM | Moment: ${run["nm"]} Nm'),
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: Colors.blueAccent,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedRuns.add(index);
                          } else {
                            selectedRuns.remove(index);
                          }
                        });
                      },
                    ),
                    onTap: () {
                      // Pozwala zaznaczać klikając w cały kafelek
                      setState(() {
                        if (isSelected) {
                          selectedRuns.remove(index);
                        } else {
                          selectedRuns.add(index);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
          
          // Przycisk "PORÓWNAJ" pojawia się tylko wtedy, gdy zaznaczysz min. 2 pomiary
          if (selectedRuns.length >= 2)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.stacked_line_chart, color: Colors.white),
                  label: Text(
                    'PORÓWNAJ ${selectedRuns.length} WYKRESY',
                    style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    debugPrint("Przechodzę do ekranu nakładania wykresów!");
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}