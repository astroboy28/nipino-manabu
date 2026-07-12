c = open('lib/screens/quiz/quiz_screen.dart', encoding='utf-8').read()

# Find the GridView section
start = c.find('              GridView.count(')
# Find the end - the comma after the closing parenthesis of GridView
# We need to find the matching closing ),
depth = 0
i = start
while i < len(c):
    if c[i] == '(':
        depth += 1
    elif c[i] == ')':
        depth -= 1
        if depth == 0:
            end = i + 2  # include the comma and newline
            break
    i += 1

old = c[start:end]
print("Found section, length:", len(old))

new = '''              // -- Options ----------------------------------------------------------
              if (q.isListening || q.questionType == 'grammar_fill')
                Column(
                  children: List.generate(q.options.length, (i) {
                    Color border = AppColors.border;
                    Color bg     = AppColors.bg;
                    Color text   = AppColors.ink;
                    Color labelBg = AppColors.bg3;
                    Color labelText = AppColors.muted;
                    if (_revealed) {
                      if (i == q.correctIndex) {
                        border = AppColors.green; bg = AppColors.greenLight;
                        text = AppColors.green; labelBg = AppColors.green;
                        labelText = Colors.white;
                      } else if (i == _selected) {
                        border = AppColors.red; bg = AppColors.redLight;
                        text = AppColors.red; labelBg = AppColors.red;
                        labelText = Colors.white;
                      }
                    }
                    return GestureDetector(
                      onTap: _revealed ? null : () => _pickAnswer(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                            color: bg,
                            border: Border.all(color: border, width: 1.5),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                                color: labelBg,
                                borderRadius: BorderRadius.circular(4)),
                            child: Center(child: Text(
                                ['A','B','C','D'][i],
                                style: TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: labelText))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(q.options[i],
                              style: TextStyle(
                                  fontFamily: 'NotoSansJP', fontSize: 14,
                                  fontWeight: FontWeight.w600, color: text))),
                        ]),
                      ),
                    );
                  }),
                )
              else
                GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8, crossAxisSpacing: 8,
                childAspectRatio: 1.7,
                children: List.generate(q.options.length, (i) {
                  Color border = AppColors.border;
                  Color bg     = AppColors.bg;
                  Color text   = AppColors.ink;
                  if (_revealed) {
                    if (i == q.correctIndex) {
                      border = AppColors.green; bg = AppColors.greenLight;
                      text = AppColors.green;
                    } else if (i == _selected) {
                      border = AppColors.red; bg = AppColors.redLight;
                      text = AppColors.red;
                    }
                  }
                  return GestureDetector(
                    onTap: _revealed ? null : () => _pickAnswer(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: bg,
                          border: Border.all(color: border, width: 1.5),
                          borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text(q.options[i],
                          style: TextStyle(
                              fontFamily: 'NotoSansJP', fontSize: 16,
                              fontWeight: FontWeight.w700, color: text),
                          textAlign: TextAlign.center)),
                    ),
                  );
                }),
              ),
'''

c = c[:start] + new + c[end:]
open('lib/screens/quiz/quiz_screen.dart', 'w', encoding='utf-8').write(c)
print("Done!")
