---
html-base-img: ../
---

# Ссылочные изображения

[before]: img/nature.png "Определение до использования"

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

Намеренно отсутствующий файл для проверки PDF fallback: ![Отсутствующее изображение][missing-file].

Неизвестная метка остаётся текстом: ![Неизвестное][missing].

Некорректное определение не разрешается: ![Некорректное][broken].

[full ref]: img/cats(1).png "Полный title"
[Свёрнутое описание]: img/megapolis%20skyline.jpg 'Свёрнутый title'
[Короткое описание]: img/cats(1).png (Короткий title)
[formatted]: img/nature.png "Форматированный alt"
[html-escape]: img/cats(1).png "Title & <tag>"
[straße]: img/megapolis%20skyline.jpg
[space label]: img/nature.png
[escaped\!]: img/cats(1).png
[duplicate]: img/nature.png
[duplicate]: img/megapolis%20skyline.jpg
[angle]: <img/megapolis skyline.jpg>
[escaped]: img/cats\(1\).png "Кавычка: \" и скобка: \)"
[deep-url]: img/a(b(c(d(e))))/nature.png
[multiline]:
    img/megapolis%20skyline.jpg
    "Первая строка
    вторая строка"
[empty-title]: img/cats(1).png ""
[empty-url]: <> "Пустой URL"
[empty-alt]: img/nature.png
[unused]: img/megapolis%20skyline.jpg
[real-image]: img/megapolis%20skyline.jpg "Реальное изображение"
[missing-file]: img/does-not-exist.png
[broken]: img/nature.png "Незакрытый title

> [quote-ref]: img/nature.png "Определение в цитате"

> [nested-first]: img/cats(1).png

[nested-first]: img/nature.png

- Пункт с определением

    [list-ref]: img/megapolis%20skyline.jpg "Определение в списке"

- [empty-list]: img/cats(1).png "Пустой пункт"

- Внешний пункт

    - Вложенный пункт

        [nested-ref]: img/nature.png "Определение во вложенном списке"
