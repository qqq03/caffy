"""
학습 데이터셋 관리 서비스
"""

import os
import json
import uuid
import hashlib
from datetime import datetime
from pathlib import Path
from typing import Optional, List


class DatasetService:
    def __init__(self):
        self.base_path = Path(os.getenv("DATASET_PATH", "./dataset"))
        self.images_path = self.base_path / "images"
        self.labels_file = self.base_path / "labels.json"
        
        # 디렉토리 생성
        self.images_path.mkdir(parents=True, exist_ok=True)
        
        # 라벨 파일 초기화
        if not self.labels_file.exists():
            self._save_labels({})
    
    def _load_labels(self) -> dict:
        """라벨 파일 로드"""
        if self.labels_file.exists():
            with open(self.labels_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {}
    
    def _save_labels(self, labels: dict):
        """라벨 파일 저장"""
        with open(self.labels_file, "w", encoding="utf-8") as f:
            json.dump(labels, f, ensure_ascii=False, indent=2)
    
    def _generate_image_hash(self, image_bytes: bytes) -> str:
        """이미지 해시 생성"""
        return hashlib.sha256(image_bytes).hexdigest()[:16]
    
    async def save_image(
        self,
        image_bytes: bytes,
        drink_name: Optional[str] = None,
        brand: Optional[str] = None,
        caffeine_amount: Optional[int] = None,
        filename: Optional[str] = None
    ) -> dict:
        """
        이미지를 데이터셋에 저장합니다.
        """
        # 이미지 ID 생성
        image_hash = self._generate_image_hash(image_bytes)
        image_id = f"{image_hash}_{uuid.uuid4().hex[:8]}"
        
        # 파일 확장자 추출
        ext = "jpg"
        if filename:
            ext = filename.split(".")[-1].lower()
            if ext not in ["jpg", "jpeg", "png", "webp"]:
                ext = "jpg"
        
        # 이미지 저장
        image_path = self.images_path / f"{image_id}.{ext}"
        with open(image_path, "wb") as f:
            f.write(image_bytes)
        
        # 라벨 저장
        labels = self._load_labels()
        labels[image_id] = {
            "id": image_id,
            "image_path": str(image_path),
            "drink_name": drink_name,
            "brand": brand,
            "caffeine_amount": caffeine_amount,
            "verified": False,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        self._save_labels(labels)
        
        return labels[image_id]
    
    async def get_all(
        self,
        skip: int = 0,
        limit: int = 100,
        verified_only: bool = False
    ) -> List[dict]:
        """
        데이터셋 항목들을 조회합니다.
        """
        labels = self._load_labels()
        items = list(labels.values())
        
        if verified_only:
            items = [item for item in items if item.get("verified", False)]
        
        # 정렬 (최신순)
        items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        
        return items[skip:skip + limit]
    
    async def update_label(
        self,
        image_id: str,
        drink_name: str,
        brand: Optional[str] = None,
        caffeine_amount: Optional[int] = None
    ) -> dict:
        """
        데이터셋 항목의 라벨을 수정합니다.
        """
        labels = self._load_labels()
        
        if image_id not in labels:
            raise ValueError(f"이미지를 찾을 수 없습니다: {image_id}")
        
        labels[image_id].update({
            "drink_name": drink_name,
            "brand": brand,
            "caffeine_amount": caffeine_amount,
            "verified": True,
            "updated_at": datetime.now().isoformat()
        })
        
        self._save_labels(labels)
        return labels[image_id]
    
    async def get_stats(self) -> dict:
        """
        데이터셋 통계를 반환합니다.
        """
        labels = self._load_labels()
        items = list(labels.values())
        
        verified_count = sum(1 for item in items if item.get("verified", False))
        
        # 음료별 통계
        drink_counts = {}
        for item in items:
            name = item.get("drink_name", "Unknown")
            drink_counts[name] = drink_counts.get(name, 0) + 1
        
        return {
            "total": len(items),
            "verified": verified_count,
            "unverified": len(items) - verified_count,
            "by_drink": drink_counts
        }
    
    async def delete_item(self, image_id: str) -> bool:
        """
        데이터셋 항목을 삭제합니다.
        """
        labels = self._load_labels()
        
        if image_id not in labels:
            return False
        
        # 이미지 파일 삭제
        image_path = Path(labels[image_id]["image_path"])
        if image_path.exists():
            image_path.unlink()
        
        # 라벨 삭제
        del labels[image_id]
        self._save_labels(labels)
        
        return True
