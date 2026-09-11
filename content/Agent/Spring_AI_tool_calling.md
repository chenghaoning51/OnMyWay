+++
title = 'Spring AI Tool Calling 使用指南'
slug = "spring-ai-tool-calling"
date = 2026-09-06T00:00:00+08:00
lastmod = 2026-09-06T00:00:00+08:00
weight = 3
categories = ['Agent']
tags = ['Agent', 'Spring AI']
description = 'ToolCalling(FunctionCalling)允许模型与一组API或者工具进行交互,增强模型的能力……'
+++

# Spring AI Tool Calling使用指南之我不用JAVA好多年

## 概述:

Tool Calling(Function Calling)允许模型与一组API或者工具进行交互,增强模型的能力

主要功能:

- 信息检索:从外部数据源获取信息,比如:数据库,Web服务,例如:Web_Search
- 执行操作:在软件系统执行特定操作:例如:预定航班,生成代码

Spring AI Alibaba拓展服务:

- 搜索引擎
- 翻译服务
- 地图服务
- 数据服务
- 开发工具
- 其他工具

## 详细使用说明

## **Python Tool示例**(你个臭执行Python代码的)

`PythonTool` 使用 GraalVM polyglot 在沙箱环境中执行 Python 代码。这个工具允许 AI 代理执行 Python 代码片段并获取结果。

### 依赖配置:

使用Maven添加依赖:

```
<dependency>
	<groupId>com.alibaba.cloud.ai</groupId>
	<artifactId>spring-ai-alibaba-starter-tool-calling-python</artifactId>
	<version>${version}</version>
</dependency>
```

**注意**：Python Tool 需要 GraalVM polyglot 依赖，这些依赖已作为可选依赖包含。如果需要使用，请确保 GraalVM polyglot 在 classpath 中。

### 自动配置

Python Tool默认启用,会自动注册为ToolCallback并可供AI代理使用,如果需要禁用,可以在配置文件中设置


```
spring:
	ai:
		alibaba:
			python:
				tool:
					enabled: false
```

### 基本使用

#### 示例1:在ChatClient中使用

```
import com.alibaba.cloud.ai.agent.python.tool.PythonTool;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class PythonToolService {

    @Autowired
    private ChatModel chatModel;

    @Autowired
    private PythonTool pythonTool;

    public String executeCalculation(String question) {
        // 创建 ChatClient 并添加 Python Tool
        ChatClient chatClient = ChatClient.builder(chatModel)
            .tools(pythonTool.createPythonToolCallback(PythonTool.DESCRIPTION))
            .build();

        // 使用工具进行对话
        String response = chatClient.prompt(question)
            .call()
            .content();

        return response;
    }
}
```

#### 示例2:直接使用PythonTool

```
import com.alibaba.cloud.ai.agent.python.tool.PythonTool;
import org.springframework.ai.chat.model.ToolContext;

public class DirectPythonToolUsage {

    public void executePythonCode() {
        PythonTool pythonTool = new PythonTool();
        
        // 创建请求
        PythonTool.PythonRequest request = new PythonTool.PythonRequest("2 + 2");
        
        // 执行 Python 代码
        String result = pythonTool.apply(request, new ToolContext());
        
        System.out.println("Result: " + result); // 输出: Result: 4
    }
}
```

#### 示例3:执行复杂计算

还是通过在client中调用PythonTool

#### 示例4:字符串操作

类似于示例2:创建request,调用apply(request,toolcontext)

```
  PythonTool.PythonRequest request1 = new PythonTool.PythonRequest(
            "'Hello, ' + 'World'"
        );
        String result1 = pythonTool.apply(request1, toolContext);
```

#### 示例5:在Spring Boot应用中使用

类似于示例1
创建client并将PythonTool写入,只是这里的1应用场景是Spring Boot

#### 示例6:自定义ToolCallback

(来你告诉我这不是在Spring Boot里面运行吗?)


```
import com.alibaba.cloud.ai.agent.python.tool.PythonTool;
import org.springframework.ai.tool.ToolCallback;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class PythonToolConfiguration {

    @Bean
    public PythonTool pythonTool() {
        return new PythonTool();
    }

    @Bean
    public ToolCallback pythonToolCallback(PythonTool pythonTool) {
        return PythonTool.createPythonToolCallback(
            "执行 Python 代码并返回结果。支持数学计算、字符串处理、列表操作等。"
        );
    }
}
```

#### 示例7:多工具组合使用

PythonTool和其他Tool一起调用,看看就好,也是创建client并添加tools,这次是多个

### 安全特性:

PythonTool在沙箱环境中运行,具有以下的安全限制

- 文件I/O已禁用:无法读写文件
- 本地访问已禁用:无法访问本地系统资源
- 进程创建已禁用:无法创建新的进程
- 默认限制所有访问:所有访问受限

保证了Python代码执行的安全性

### 支持的数据类型

- 字符串:直接返回
- 数字:转化为字符串返回
- 布尔值:转化为字符串返回
- 数组/列表:转化为字符串表现形式
- 其他类型:使用toString()方法转换

### 注意事项

1. **GraalVM 依赖**：确保 GraalVM polyglot 依赖在 classpath 中
2. **性能考虑**：每次执行都会创建新的 Context，对于频繁调用可能需要优化
3. **错误处理**：代码执行错误会被捕获并返回错误消息
4. **代码限制**：由于安全限制，某些 Python 功能可能不可用
5. **资源管理**：Context 会自动关闭，无需手动管理

### 一个完整的示例:AI代理使用Python Tool:

eee,这算哪门子示例,好吧也算

```
import com.alibaba.cloud.ai.agent.python.tool.PythonTool;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.stereotype.Service;

@Service
public class PythonToolAgentService {

    private final ChatClient chatClient;

    public PythonToolAgentService(ChatModel chatModel, PythonTool pythonTool) {
        this.chatClient = ChatClient.builder(chatModel)
            .tools(pythonTool.createPythonToolCallback(PythonTool.DESCRIPTION))
            .build();
    }

    public String solveMathProblem(String problem) {
        String prompt = String.format("""
            请使用 Python 工具解决以下数学问题：
            %s
            
            请展示计算过程。
            """, problem);

        return chatClient.prompt(prompt)
            .call()
            .content();
    }

    public String analyzeData(String dataDescription) {
        String prompt = String.format("""
            请使用 Python 工具分析以下数据：
            %s
            
            请计算基本统计信息（平均值、中位数、标准差等）。
            """, dataDescription);

        return chatClient.prompt(prompt)
            .call()
            .content();
    }
}
```

### 支持的拓展实现:

https://java2ai.com/integration/toolcalls/tool-calls#%E7%9B%AE%E5%BD%95
自己去这里看

### 使用说明

所有的Tool Calling实现都遵循相同的使用模式

1. 添加依赖:在pom.xml或者build.gradle中添加相应的依赖
2. 自动配置:Spring Boot的生态真实太好用了,你们知道吗?**会自动注册为ToolCallback**
3. 在Chatclient中使用:通过ChatClient.builder().tools()添加工具
4. AI模型调用:AI模型会根据会话内容自动决定是否调用工具

### 通用接口

你这么好用你不早说?

所有 Tool 都实现了 `BiFunction<Request, ToolContext, String>` 接口，并通过 `FunctionToolCallback` 包装为 `ToolCallback`：

```java
public interface ToolCallback {
    String getName();
    String getDescription();
    ToolResponse call(ToolRequest request);
}
```

### 配置说明

大多数工具都支持通过Spring Boot配置属性进行配置(又是你宝宝)

```
spring:
  ai:
    alibaba:
      tool-name:
        enabled: true  # 启用/禁用工具
        # 其他工具特定配置
```

### 认证和API key

参考各个工具的文档

### 最佳实践

1. **工具选择**：根据实际需求选择合适的工具，避免添加不必要的工具
2. **错误处理**：工具调用可能失败，确保有适当的错误处理机制
3. **性能优化**：对于频繁调用的工具，考虑缓存结果
4. **安全性**：确保 API Key 等敏感信息的安全存储
5. **成本控制**：某些工具（如搜索、翻译）可能产生费用，注意使用量