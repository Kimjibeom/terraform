import subprocess
import time
import json

def wait_for_terraform_output(output_key, cwd="terraform_project", timeout=60, interval=5):
    """Terraform output을 polling해서 특정 key가 나올 때까지 대기"""
    start = time.time()
    while time.time() - start < timeout:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=cwd,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            try:
                outputs = json.loads(result.stdout)
                if output_key in outputs and outputs[output_key]["value"]:
                    return outputs
            except json.JSONDecodeError:
                pass
        time.sleep(interval)
    raise TimeoutError(f"'{output_key}' output을 {timeout}초 내에 가져오지 못했습니다.")
