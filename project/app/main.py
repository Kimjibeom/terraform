from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import subprocess
from app.utils.terraform import wait_for_terraform_output

app = FastAPI()

class EC2Request(BaseModel):
    region: str
    ami: str
    instance_type: str
    key_name: str

@app.post("/provision")
def provision_instance(req: EC2Request):
    try:
        # 1. Terraform apply
        provision_cmd = [
            "ansible-playbook", "ansible/playbook.yml",
            "-e", f"region={req.region}",
            "-e", f"ami={req.ami}",
            "-e", f"instance_type={req.instance_type}",
            "-e", f"key_name={req.key_name}"
        ]
        provision_result = subprocess.run(provision_cmd, capture_output=True, text=True)
        if provision_result.returncode != 0:
            raise HTTPException(status_code=500, detail=provision_result.stderr)

        # 2. Terraform output 기다림
        outputs = wait_for_terraform_output("public_ips")

        # 3. Terraform output 기반 inventory 파일 생성
        inventory_result = subprocess.run(
            ["ansible-playbook", "ansible/dynamic_inventory_setup.yml"],
            capture_output=True, text=True
        )
        if inventory_result.returncode != 0:
            raise HTTPException(status_code=500, detail=inventory_result.stderr)

        # 4. 생성된 인벤토리로 후속 설정 수행
        post_config_result = subprocess.run(
            ["ansible-playbook", "-i", "inventory/provisioned.ini", "ansible/post_config_playbook.yml"],
            capture_output=True, text=True
        )
        if post_config_result.returncode != 0:
            raise HTTPException(status_code=500, detail=post_config_result.stderr)

        return {
            "message": "Provisioning and post configuration completed",
            "public_ips": outputs.get("public_ips", {}).get("value", []),
            "instance_ids": outputs.get("instance_ids", {}).get("value", []),
            "terraform": provision_result.stdout,
            "inventory": inventory_result.stdout,
            "post_config": post_config_result.stdout
        }

    except TimeoutError as te:
        raise HTTPException(status_code=504, detail=str(te))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
