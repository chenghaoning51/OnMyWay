+++
title = 'Spring AI Tools'
slug = "spring-ai-tools"
date = 2026-09-06T00:00:00+08:00
lastmod = 2026-09-06T00:00:00+08:00
weight = 2
categories = ['Agent']
tags = ['Agent', 'Spring AI']
description = 'Tool是agents调用来执行操作的组件,通过定义良好的输入和输出来让模型和外部世界交互……'
+++

# Tools

## 定义:

Tool是agents调用来执行操作的组件,通过**定义良好的输入和输出**来让模型和外部世界交互

Tools封装了一个可调用的函数及其输入模式,允许模型决定什么时候调用Tools以及传入的参数


Tool主要用语言:	

- 信息检索:与外部数据源进行交互检索信息,如数据库和Web搜索引擎.主要目标是增强model的知识,使其能够回答原本无法回答的问题
- 执行操作:目标是自动化原本需要人工干预或者显式编程的任务

ps:Toolc calling称为model能力但是实际上由客户端提供ToolCalling逻辑

## Quick Start

两个示例:一个信息检索,一个执行操作

### 信息检索

在DataTimeTool类中实现一个Tool来获取日期和时间(此处不关心具体实现方式)

```
import java.time.LocalDateTime;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.context.i18n.LocaleContextHolder;

class DateTimeTools {

  @Tool(description = "Get the current date and time in the user's timezone")
  String getCurrentDateTime() {
      return LocalDateTime.now().atZone(LocaleContextHolder.getTimeZone().toZoneId()).toString();
  }

}
```

如何让LLM了解到这个Tool的存在:通过调用Chatclient的tool()方法通知LLM
注意 tool(datetimetool)中的datetimetool需要实例化(也就你JAVA这么多事)

```
ChatModel chatModel = ...;

String response = ChatClient.create(chatModel)
      .prompt("What day is tomorrow?")
      .tools(new DateTimeTools())
      .call()
      .content();

System.out.println(response);
// 输出：Tomorrow is 2015-10-21.
```

### 执行操作

和上面差不多自己看了

```
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.context.i18n.LocaleContextHolder;

class DateTimeTools {

  @Tool(description = "Get the current date and time in the user's timezone")
  String getCurrentDateTime() {
      return LocalDateTime.now().atZone(LocaleContextHolder.getTimeZone().toZoneId()).toString();
  }

  @Tool(description = "Set a user alarm for the given time, provided in ISO-8601 format")
  void setAlarm(String time) {
      LocalDateTime alarmTime = LocalDateTime.parse(time, DateTimeFormatter.ISO_DATE_TIME);
      System.out.println("Alarm set for " + alarmTime);
  }

}
```

那么有的同学就要问了:
这里只调用了datetimetool类而不是具体的工具,他是怎么知道选择哪个方法的
这就是你SpringAI叔叔的强大之处了,@Tool:会将该方法自动注册为一个tool
所以你们臭学JAVA的还不好好学Spring,Spring Boot,Spring MVC?

### 概述

![Tool Calling 主要操作序列](https://java2ai.com/assets/images/tool-calling-01-f574ce40dfbd8203a4f5f0c08256258e.jpg)

1.Tool定义:名称,描述和传入参数
2.调用:Model发送带有Tool名称和参数的相应
3.通过名称选择tool并传入参数执行
4.toolcall结果由程序处理
5.结果传回Model
6.Model根据结果作为附加上下文生成最终响应

Tools 是 tool calling 的构建块，它们由 `ToolCallback` 接口建模。Spring AI 提供了从方法和函数指定 `ToolCallback`(s) 的内置支持，但您始终可以定义自己的 `ToolCallback` 实现以支持更多用例。

`ChatModel` 实现透明地将 tool call 请求分派到相应的 `ToolCallback` 实现，并将 tool call 结果发送回 model，最终生成最终响应。它们使用 `ToolCallingManager` 接口来执行此操作，该接口负责管理 tool 执行生命周期。

`ChatClient` 和 `ChatModel` 都接受 `ToolCallback` 对象列表，以使 tools 可用于 model 和最终执行它们的 `ToolCallingManager`。

除了直接传递 `ToolCallback` 对象外，您还可以传递 tool 名称列表，这些名称将使用 `ToolCallbackResolver` 接口动态解析。

## 创建工具

Spring AI提供了两种从方法指定Tools(即ToolCallback(s))的内置支持

- 声明式:使用@Tool注解
- 编程式:使用低级MethodToolCallback实现

### 方法作为Tool

#### 声明式规范 @Tool

```
class DateTimeTools {

  @Tool(description = "Get the current date and time in the user's timezone")
  String getCurrentDateTime() {
      return LocalDateTime.now().atZone(LocaleContextHolder.getTimeZone().toZoneId()).toString();
  }

}
```

@Tool注解允许你提供的信息:

- name:如果未提供,将使用方法名称
- description:tool描述;若未提供,使用方法名称代替.但是强烈建议详细描述,对于model理解tool的用途以及when to use and how to use很重要
- returnDirect:结果是否直接传回model;为布尔值
- resultConverter:将toolcall的结果转化为String Object以 `ToolCallResultConverter` 实现

**NOTE:** Spring AI 为 `@Tool` 注解方法的 AOT 编译提供内置支持，只要包含方法的类是 Spring bean（例如 `@Component`）。否则，您需要向 GraalVM 编译器提供必要的配置。例如，通过用 `@RegisterReflection(memberCategories = MemberCategory.INVOKE_DECLARED_METHODS)` 注解类。

如果方法返回值，返回类型**必须是可序列化类型**，因为结果将被序列化并发送回 model。

`@ToolParam` 注解可用于提供有关输入参数的附加信息，例如描述或参数是必需还是可选的。默认情况下，所有输入参数都被视为必需

```
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

class DateTimeTools {

  @Tool(description = "Set a user alarm for the given time")
  void setAlarm(@ToolParam(description = "Time in ISO-8601 format") String time) {
      LocalDateTime alarmTime = LocalDateTime.parse(time, DateTimeFormatter.ISO_DATE_TIME);
      System.out.println("Alarm set for " + alarmTime);
  }

}
```

@ToolParam允许你提供的有关tool参数的关键信息:

- `description`：参数的描述，model 可以使用它来更好地理解如何使用它。例如，参数应该是什么格式，允许什么值等。
- `required`：参数是必需还是可选的。默认情况下，所有参数都被视为必需。

