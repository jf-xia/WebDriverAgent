#!/usr/bin/env python3
"""
JSON转YAML脚本 - 移除空值属性，输出紧凑YAML
用法: python3 json_to_yaml.py [input.json] [output.yaml]
"""

import json
import yaml
import sys
import os

def remove_empty(obj):
    """递归移除空值（None、空字符串、空列表、空字典）"""
    if isinstance(obj, dict):
        # 移除空值键值对
        cleaned = {}
        for k, v in obj.items():
            cleaned_v = remove_empty(v)
            # 保留非空值
            if cleaned_v is not None and cleaned_v != "" and cleaned_v != [] and cleaned_v != {}:
                cleaned[k] = cleaned_v
        return cleaned if cleaned else None
    elif isinstance(obj, list):
        # 移除空值列表项
        cleaned = []
        for item in obj:
            cleaned_item = remove_empty(item)
            if cleaned_item is not None and cleaned_item != "" and cleaned_item != [] and cleaned_item != {}:
                cleaned.append(cleaned_item)
        return cleaned if cleaned else None
    else:
        # 基本类型，直接返回
        return obj

def optimize_rect(obj):
    """优化rect对象：删除width和height，只保留x和y"""
    if isinstance(obj, dict):
        if 'rect' in obj and isinstance(obj['rect'], dict):
            rect = obj['rect']
            # 只保留x和y，删除width和height
            optimized_rect = {}
            if 'x' in rect:
                optimized_rect['x'] = rect['x']
            if 'y' in rect:
                optimized_rect['y'] = rect['y']
            obj['rect'] = optimized_rect
        # 递归处理子节点
        for key, value in obj.items():
            if isinstance(value, (dict, list)):
                obj[key] = optimize_rect(value)
    elif isinstance(obj, list):
        # 递归处理列表中的每个元素
        for i in range(len(obj)):
            obj[i] = optimize_rect(obj[i])
    return obj

def filter_zero_position(obj):
    """过滤掉x和y都是0且没有标识信息的元素（位置在原点的元素）"""
    if isinstance(obj, dict):
        # 检查当前元素是否有rect且x=0, y=0
        if 'rect' in obj and isinstance(obj['rect'], dict):
            rect = obj['rect']
            if rect.get('x') == 0 and rect.get('y') == 0:
                # 检查是否有标识信息（name、label、value、rawIdentifier）
                has_identifier = (
                    obj.get('name') or 
                    obj.get('label') or 
                    obj.get('value') or 
                    obj.get('rawIdentifier')
                )
                # 如果是叶子节点（没有children）且没有标识信息，则过滤掉
                if ('children' not in obj or not obj['children']) and not has_identifier:
                    return None
        # 递归处理子节点
        if 'children' in obj and isinstance(obj['children'], list):
            filtered_children = []
            for child in obj['children']:
                filtered_child = filter_zero_position(child)
                if filtered_child is not None:
                    filtered_children.append(filtered_child)
            obj['children'] = filtered_children
            # 如果过滤后没有子节点，且当前节点也在原点且没有标识信息，则过滤掉当前节点
            if not filtered_children and 'rect' in obj and isinstance(obj['rect'], dict):
                rect = obj['rect']
                if rect.get('x') == 0 and rect.get('y') == 0:
                    has_identifier = (
                        obj.get('name') or 
                        obj.get('label') or 
                        obj.get('value') or 
                        obj.get('rawIdentifier')
                    )
                    if not has_identifier:
                        return None
        return obj
    elif isinstance(obj, list):
        # 递归处理列表中的每个元素
        filtered = []
        for item in obj:
            filtered_item = filter_zero_position(item)
            if filtered_item is not None:
                filtered.append(filtered_item)
        return filtered if filtered else None
    else:
        return obj

def flatten_children(obj):
    """将children字段的内容提升到父层级，删除children字段"""
    if isinstance(obj, dict):
        # 如果有children字段
        if 'children' in obj and isinstance(obj['children'], list):
            # 删除children字段，将子元素作为当前对象的属性
            children = obj.pop('children')
            # 如果children只有一个元素，可以直接合并
            if len(children) == 1:
                child = children[0]
                # 将child的属性合并到当前对象
                for key, value in child.items():
                    if key not in obj:  # 不覆盖已有属性
                        obj[key] = value
                # 递归处理合并后的内容
                obj = flatten_children(obj)
            else:
                # 如果有多个children，保留为列表
                # 使用一个简单的属性名，比如'items'或直接使用父元素类型
                # 这里我们使用'items'作为通用属性名
                obj['items'] = children
                # 递归处理每个子元素
                for i in range(len(obj['items'])):
                    obj['items'][i] = flatten_children(obj['items'][i])
        else:
            # 递归处理其他字段
            for key, value in obj.items():
                if isinstance(value, (dict, list)):
                    obj[key] = flatten_children(value)
    elif isinstance(obj, list):
        # 递归处理列表中的每个元素
        for i in range(len(obj)):
            obj[i] = flatten_children(obj[i])
    return obj

def main():
    # 默认文件路径
    input_file = "source.json"
    output_file = "source_optimized.yaml"
    
    # 命令行参数
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]
    
    # 检查输入文件
    if not os.path.exists(input_file):
        print(f"错误: 输入文件不存在: {input_file}")
        sys.exit(1)
    
    print(f"读取JSON: {input_file}")
    
    # 读取JSON
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 移除空值
    print("移除空值属性...")
    cleaned_data = remove_empty(data)
    
    # 优化rect对象
    print("优化rect对象（删除width和height）...")
    cleaned_data = optimize_rect(cleaned_data)
    
    # 过滤原点元素
    print("过滤x=0,y=0的元素...")
    cleaned_data = filter_zero_position(cleaned_data)
    
    # 扁平化children结构
    print("扁平化children结构...")
    cleaned_data = flatten_children(cleaned_data)
    
    # 统计信息
    original_size = os.path.getsize(input_file)
    print(f"原始JSON大小: {original_size} bytes")
    
    # 转换为YAML
    print(f"转换为YAML: {output_file}")
    
    # 使用紧凑的YAML格式
    yaml_content = yaml.dump(
        cleaned_data, 
        default_flow_style=False,  # 使用块状格式，更易读
        allow_unicode=True,        # 支持Unicode
        sort_keys=False,           # 保持原始键顺序
        width=1000,                # 避免自动换行
        indent=2                   # 使用2空格缩进
    )
    
    # 写入YAML文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(yaml_content)
    
    # 统计输出大小
    output_size = os.path.getsize(output_file)
    print(f"YAML大小: {output_size} bytes")
    print(f"压缩比: {output_size/original_size*100:.1f}%")
    
    # 统计行数
    with open(output_file, 'r', encoding='utf-8') as f:
        line_count = sum(1 for _ in f)
    print(f"YAML行数: {line_count}")
    
    print("完成！")

if __name__ == "__main__":
    main()