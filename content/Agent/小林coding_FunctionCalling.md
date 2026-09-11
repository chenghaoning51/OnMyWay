# Function Call是什么?

## 实现了从只会说话到能做事情

生成文本->Function_Call->操作外部程序

## Function Call的工作原理:

分为四步:定义函数->选择函数(模型选择)->执行函数->返回结果(生成回答)

### 定义函数:

用JSON格式描述:函数名称(name),功能说明(description),参数(params)

```
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "获取指定城市的实时天气",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {
              "type": "string", 
              "description": "城市名称，比如：上海"
            }
          },
          "required": ["city"]
        }
      }
    }
  ]
}
```

### 模型判断:

LLM分析意图并调用函数

### 执行函数

LLM本身不执行函数,而是输出调用意图+函数参数,应用程序拿到指令后调用函数执行函数

### 生成回答

LLM拿到结果并执行回答

## 为什么Function Call这么重要

解决了两个问题:

1. when:什么时候调用:LLM根据用户自然语言判断意图
2. 传入什么参数:LLM从自然语言结构化传入参数

最底层的技术基础