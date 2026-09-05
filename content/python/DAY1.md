+++
title = 'DAY1 · Python 交互模式随手记'
slug = "python-day1"
date = 2026-09-04T00:00:00+08:00
lastmod = 2026-09-04T00:00:00+08:00
weight = 1
categories = ['Python']
tags = ['解释器', '交互模式']
description = 'Python 解释器交互模式下的第一天随手记：命令行参数、常用内建用法与踩到的语法坑。'
+++

## What is shown here is what idk before!

### 此处的应用场景是python解释器的交互模式之下:

Do not laugh at me ! I'm REALLY a newbie!!!!

```python
python -c command arg
python -m module arg
//创建新New—Item name（真实的名称） ItemType type（具体的类型）
```

忘掉了的

#### 数字

除法运算 (`/`) 总是返回浮点数。**如果要做 [floor division](https://docs.python.org/zh-cn/3/glossary.html#term-floor-division) 得到一个整数结果你可以使用 `//` 运算符；**

Something New：
Python 用 `**` 运算符计算乘方 [[1\]](https://docs.python.org/zh-cn/3/tutorial/introduction.html#id3)：
交互模式下，上次输出的表达式会赋给变量 `_`。把 Python 当作计算器时，用该变量实现下一步计算更简单，例如：

```
tax = 12.5 / 100
price = 100.50
price * tax
12.5625
price + _
113.0625
round(_, 2)
113.06
```

除了 [`int`](https://docs.python.org/zh-cn/3/library/functions.html#int) 和 [`float`](https://docs.python.org/zh-cn/3/library/functions.html#float)，Python 还支持其他数字类型，例如 [`Decimal`](https://docs.python.org/zh-cn/3/library/decimal.html#decimal.Decimal) 或 [`Fraction`](https://docs.python.org/zh-cn/3/library/fractions.html#fractions.Fraction)。 Python 还内置支持 [复数](https://docs.python.org/zh-cn/3/library/stdtypes.html#typesnumeric)，后缀 `j` 或 `J` 用于表示虚数 (例如 `3+5j`)。(wow 复数，之前没有了解过这个表达形式)


#### 文本：有str类型表示

‘’ 和 ‘’  “无差别
要标示引号本身，我们需要对它进行“转义”，**即在前面加一个 `\`**。或者，我们也可以使用不同类型的引号:
如果要在str使用‘ ，我们可以整体上使用“  ”反之亦然；不过统一的\貌似是一个更好的选择如果不希望前置 `\` 的字符转义成特殊字符，可以使用 *原始字符串*，在引号前添加 `r` 即可：

Copy

```python
print('C:\this\name')  # 这里 \t 表示制表符，\n 表示换行符
C:      his
ame
print(r'C:\this\name')  # 请注意引号前的 r
C:\this\name
```

原始字符串还有一个微妙的限制：一个原始字符串不能以奇数个 `\` 字符结束；请参阅 [此 FAQ 条目](https://docs.python.org/zh-cn/3/faq/programming.html#faq-programming-raw-string-backslash) 了解更多信息及绕过的办法。字符串字面值可以跨越多行。 一种做法是使用三重引号: `"""..."""` 或 `'''...'''`。 行结束符会自动包括在字符串中，但可以通过在行尾添加 `\` 来避免此行为。在下面的例子中，开头的换行符将不会被包括:

```python
print("""\
Usage: thingy [OPTIONS]
     -h                        Display this usage message
     -H hostname               Hostname to connect to
""")
Usage: thingy [OPTIONS]
     -h                        Display this usage message
     -H hostname               Hostname to connect to
```



字符串字面值的自动拼接

相邻的两个或多个 *字符串字面值* （引号标注的字符）会自动合并：

```
'Py' 'thon'
'Python'
```

拼接分隔开的长字符串时，这个功能特别实用：

```
text = ('Put several strings within parentheses '
        'to have them joined together.')
text
'Put several strings within parentheses to have them joined together.'
```

这项功能只能用于两个字面值，不能用于变量或表达式，合并变量&表达式要使用+：

Copy

```
prefix = 'Py'
prefix 'thon'  # 不能拼接变量和字符串字面值
  File "<stdin>", line 1
    prefix 'thon'
           ^^^^^^
SyntaxError: invalid syntax
('un' * 3) 'ium'
  File "<stdin>", line 1
    ('un' * 3) 'ium'
               ^^^^^
SyntaxError: invalid syntax
```

字符串的索引居然能够支持负数，从右边开始计数字符串支持 *索引* （下标访问），第一个字符的索引是 0。单字符没有专用的类型，就是长度为一的字符串：

```
word = 'Python'
word[0]  # 0 号位的字符
'P'
word[5]  # 5 号位的字符
'n'
```

索引还支持负数，用负数索引时，从右边开始计数：

```
word[-1]  # 最后一个字符
'n'
word[-2]  # 倒数第二个字符
'o'
word[-6]
'P'
```

字符串的切：用于获取子字符串（substr来了说是）

```
word[0:2]  # 从 0 号位 (含) 到 2 号位 (不含) 的字符
'Py'
word[2:5]  # 从 2 号位 (含) 到 5 号位 (不含) 的字符
'tho'
```

切片索引的默认值：

```
word[:2]   # 从开头到 2 号位 (不含) 的字符
'Py'
word[4:]   # 从 4 号位 (含) 到末尾
'on'
word[-2:]  # 从倒数第二个 (含) 到末尾
'on'
```

注意，**输出结果包含切片开始，但不包含切片结束**。因此，`s[:i] + s[i:]` 总是等于 `s`：
都是如果结束索引是默认值，那么实际上还有一个终结符，我们可以理解为不包含这个终结符但是包含最后一位
可以换一个方式理解：切片是索引之间
直接通过索引访问单个位置可能会出现索引越界，但是切片会自动处理索引越界
Python的字符串不可修改，是immutable的（怎么和JAVA一样啊，恼！！！）
字符串长度获取：内置函数：len();
我CHOVY，ntm讲字符串给我讲好了啊！！！
下面是字符串的一些方法！！！
自己去这里找
https://docs.python.org/zh-cn/3/library/stdtypes.html#textseq

#### 列表：mutable

支持索引，切片，合并
append（）；len（）：为切片赋值可以改变列表大小，甚至清空整个列表：

```
letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
letters
['a', 'b', 'c', 'd', 'e', 'f', 'g']
# 替换一些值
letters[2:5] = ['C', 'D', 'E']
letters
['a', 'b', 'C', 'D', 'E', 'f', 'g']
# 现在移除它们
letters[2:5] = []
letters
['a', 'b', 'f', 'g']
# 通过用一个空列表替代所有元素来清空列表
letters[:] = []
letters
[]
```

嵌套列表（注意不是合并哦哦哦哦哦！！！！！！）

```
a = ['a', 'b', 'c']
n = [1, 2, 3]
x = [a, n]
x
[['a', 'b', 'c'], [1, 2, 3]]
x[0]
['a', 'b', 'c']
x[0][1]
'b'
```

- 关键字参数 *end* 可以取消输出后面的换行, 或用另一个字符串结尾：

  Copy

  ```
  a, b = 0, 1
  while a < 1000:
      print(a, end=',')
      a, b = b, a+b
  
  0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,
  ```

`**` 比 `-` 的优先级更高, 所以 `-3**2` 会被解释成 `-(3**2)` ，因此，结果是 `-9`。要避免这个问题，并且得到 `9`, 可以用 `(-3)**2`。

[[2](https://docs.python.org/zh-cn/3/tutorial/introduction.html#id2)]

与其他语言不同，特殊字符如 `\n` 在单引号 (`'...'`) 和双引号 (`"..."`) 里的意义一样。 这两种引号唯一的区别是，不需要在单引号里转义双引号 `"` (但此时必须把单引号转义成 `\'`)，反之亦然。

#### 更多的控制流工具



##### range（）函数：

内置函数 [`range()`](https://docs.python.org/zh-cn/3/library/stdtypes.html#range) 用于生成等差数列：

```
for i in range(5):
    print(i)

0
1
2
3
4
```

生成的序列绝不会包括给定的终止值；`range(10)` 生成 10 个值——长度为 10 的序列的所有合法索引。range 可以不从 0 开始，且可以按给定的步长递增（即使是负数步长）：

```
list(range(5, 10))
[5, 6, 7, 8, 9]

list(range(0, 10, 3))
[0, 3, 6, 9]

list(range(-10, -100, -30))
[-10, -40, -70]
```

要按索引迭代序列，可以组合使用 [`range()`](https://docs.python.org/zh-cn/3/library/stdtypes.html#range) 和 [`len()`](https://docs.python.org/zh-cn/3/library/functions.html#len)：

```
a = ['Mary', 'had', 'a', 'little', 'lamb']
for i in range(len(a)):
    print(i, a[i])

0 Mary
1 had
2 a
3 little
4 lamb
```

不过大多数情况下 [`enumerate()`](https://docs.python.org/zh-cn/3/library/functions.html#enumerate) 函数很方便，详见 [循环的技巧](https://docs.python.org/zh-cn/3/tutorial/datastructures.html#tut-loopidioms)。

如果直接打印一个 range 会发生意想不到的事情：

```
range(10)
range(0, 10)
```

[`range()`](https://docs.python.org/zh-cn/3/library/stdtypes.html#range) 返回的对象在很多方面和列表的行为一样，但其实它和列表不一样。该对象只有在被迭代时才一个一个地返回所期望的列表项，并没有真正生成过一个含有全部项的列表，从而节省了空间。

这种对象称为可迭代对象 [iterable](https://docs.python.org/zh-cn/3/glossary.html#term-iterable)，适合作为需要获取一系列值的函数或程序构件的参数。[`for`](https://docs.python.org/zh-cn/3/reference/compound_stmts.html#for) 语句就是这样的程序构件；以可迭代对象作为参数的函数例如 [`sum()`](https://docs.python.org/zh-cn/3/library/functions.html#sum)：

```
sum(range(4))  # 0 + 1 + 2 + 3
6
```

后续我们会看到更多返回可迭代对象并以可迭代对象作为参数的函数。 在 [数据结构](https://docs.python.org/zh-cn/3/tutorial/datastructures.html#tut-structures) 一章中，我们将讨论 [`list()`](https://docs.python.org/zh-cn/3/library/stdtypes.html#list) 的更多细节。

列表的常见方法见
https://docs.python.org/zh-cn/3/tutorial/datastructures.html

```
append（value）:
extend(iterable):
insert(index,value):
remove(value):
pop(index=-1):
clear():
index(value,start,stop)
count(value);
sort(*,key=noe,reveres = False);
reveres():
copy:
```



##### 列表实现堆栈：后进先出

append();pop()

##### 列表实现队列：性能很差，最好使用collectiond.deque

##### 列表推导式:

创建列表非常方便
筛选满足某些特定条件的元素/对全部元素进行操作

##### 嵌套的列表推导式

实际应用最好用内置函数替代复杂的流程函数

##### del：区分与pop

可接单个元素如a[0],切片，或者单个变量a

##### 元组和序列

元组：通过','隔开，通常使用（）标注，imutable，但是可以存储mutable的元素如列表
特别的单个元组：

```
empty = ()
singleton = 'hello',    # <-- 注意末尾的逗号
len(empty)
0
len(singleton)
1
singleton
('hello',)
```

解包：

```
x, y, z = t
```

##### 集合：set 无序，去重

创建空集合只能用set（）；创建可以用{}和set（）；
集合推导式

##### 字典：

以key（键）为索引；任何不可变类型都可以作为key
特别的，元组仅包含（字符串，元组，数字）时也可以为key，但是如果它直接或者间接包含可变元素，则不可
键对值的集合，键唯一

下标操作d[key]可能（空值时即key不存在）会导致KeyError，最好用get（），返回值或者none：

```
list（d） ：获得所有key的列表，不包含value

sort（），in
dict（）：构造函数
```

字典推导式：关键字是比较简单的字符串时，直接用关键字参数指定键值对更便捷：

Copy

```
dict(sape=4139, guido=4127, jack=4098)
{'sape': 4139, 'guido': 4127, 'jack': 4098}
```

#### 循环的技巧

同时获得字典的（key，value） ：item（）；
同时获得（index，value）：enumerate（）；
同时循环两个或者多个序列时：zip（）；
配置这个看的更明确

```
questions = ['name', 'quest', 'favorite color']
answers = ['lancelot', 'the holy grail', 'blue']
for q, a in zip(questions, answers):
    print('What is your {0}?  It is {1}.'.format(q, a))

What is your name?  It is lancelot.
What is your quest?  It is the holy grail.
What is your favorite color?  It is blue.
```

```
逆向：reverse（）
排序：sorted（）
去重：set（）
```



#### 条件控制

```
in  ；not in
is ；not is
链式比较操作：a < b == c
优先级:not > and > or
```

###
