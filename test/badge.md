# Ссылочные изображения

[before]: images/before.png "Определение до использования"

Определение перед изображением: ![До использования][before].

Полная форма до определения: ![Полное описание][FULL REF].

Свёрнутая форма: ![Свёрнутое описание][].

Короткая форма: ![Короткое описание].

Форматированное описание: ![**Жирный** и *курсив*][formatted].

HTML-экранирование: ![<Alt & "кавычки">][html-escape].

Unicode case folding: ![Unicode][STRASSE].

Нормализация пробелов: ![Пробелы][  space   label  ].

Экранированная метка: ![Метка][escaped!].

Первое определение: ![Первое][duplicate].

Первое вложенное определение: ![Порядок][nested-first].

URL в угловых скобках: ![Угловой URL][angle].

Экранированный URL и title: ![Экранирование][escaped].

Глубоко вложенные скобки URL: ![Вложенные скобки][deep-url].

Многострочный title: ![Многострочный][multiline].

Пустой title: ![Пустой заголовок][empty-title].

Пустой URL: ![Пустой URL][empty-url].

Пустое описание: ![][empty-alt].

Определение из цитаты: ![Цитата][quote-ref].

Определение из списка: ![Список][list-ref].

Определение из пустого пункта: ![Пустой пункт][empty-list].

Определение из вложенного списка: ![Вложенный список][nested-ref].

Настоящее изображение: ![Настоящее изображение][real-image].

Неизвестная метка остаётся текстом: ![Неизвестное][missing].

Некорректное определение не разрешается: ![Некорректное][broken].

[full ref]: images/full.png "Полный title"
[Свёрнутое описание]: images/collapsed.png 'Свёрнутый title'
[Короткое описание]: images/shortcut.png (Короткий title)
[formatted]: images/formatted.png "Форматированный alt"
[html-escape]: images/html.png "Title & <tag>"
[straße]: images/unicode.png
[space label]: images/spaces.png
[escaped\!]: images/escaped-label.png
[duplicate]: images/first.png
[duplicate]: images/second.png
[angle]: <images/file with spaces.png>
[escaped]: images/file\(1\).png "Кавычка: \" и скобка: \)"
[deep-url]: images/a(b(c(d(e))))/file.png
[multiline]:
    images/multiline.png
    "Первая строка
    вторая строка"
[empty-title]: images/empty.png ""
[empty-url]: <> "Пустой URL"
[empty-alt]: images/empty-alt.png
[unused]: images/unused.png
[real-image]: ../.img.jpg "Реальное изображение"
[broken]: images/broken.png "Незакрытый title

> [quote-ref]: images/quote.png "Определение в цитате"

> [nested-first]: images/nested-first.png

[nested-first]: images/top-second.png

- Пункт с определением

    [list-ref]: images/list.png "Определение в списке"

- [empty-list]: images/empty-list.png "Пустой пункт"

- Внешний пункт

    - Вложенный пункт

        [nested-ref]: images/nested.png "Определение во вложенном списке"
